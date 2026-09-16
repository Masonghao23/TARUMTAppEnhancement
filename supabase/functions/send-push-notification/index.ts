// Deno edge function: the only place that actually calls Firebase Cloud
// Messaging. Internal-only — callable exclusively with a service_role JWT,
// never by a user's device directly. Every future notification trigger
// (attendance below 80%, class reminder, parking ending, a broadcast
// announcement, etc.) is meant to call this rather than talk to FCM
// itself, so there's exactly one place that knows how to sign a Google
// OAuth2 JWT and hit the FCM v1 API.
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

// Supabase's own gateway (verify_jwt) already checks this token's signature
// before this function ever runs, so this only needs to read the payload's
// role claim — not re-verify authenticity. Comparing against the injected
// SUPABASE_SERVICE_ROLE_KEY env var directly turned out to be unreliable on
// a project with both legacy JWT-based and newer secret-key API systems
// enabled, since it's not guaranteed to equal the legacy key you'd copy
// from the dashboard; decoding the role claim works regardless of which
// key system is active.
function jwtRole(authHeader: string): string | null {
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(padded));
    return typeof payload.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (jwtRole(authHeader) !== "service_role") {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  let body: { userId?: string; title?: string; body?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const { userId, title, body: message } = body;
  if (!userId || !title || !message) {
    return jsonResponse({ error: "userId, title, and body are required" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: keyJson, error: keyError } = await adminClient.rpc(
    "get_firebase_service_account",
  );
  if (keyError || !keyJson) {
    return jsonResponse({ error: "Firebase key not configured" }, 500);
  }
  const serviceAccount: ServiceAccount = JSON.parse(keyJson as string);

  const { data: tokenRows, error: tokenError } = await adminClient
    .from("user_fcm_tokens")
    .select("token")
    .eq("user_id", userId);

  if (tokenError) {
    return jsonResponse({ error: tokenError.message }, 500);
  }
  if (!tokenRows || tokenRows.length === 0) {
    return jsonResponse({ sent: 0, reason: "No registered devices for this user" }, 200);
  }

  const accessToken = await getAccessToken(serviceAccount);

  const results = await Promise.all(
    tokenRows.map((row) =>
      sendToToken(accessToken, serviceAccount.project_id, row.token as string, title, message)
    ),
  );

  const sent = results.filter((r) => r.ok).length;

  // FCM returns 404 (UNREGISTERED) or 400 (INVALID_ARGUMENT) for a token
  // that no longer exists — app uninstalled, or rotated without the old
  // one ever being cleaned up. Prune those so this list doesn't grow
  // stale forever and every future send doesn't keep retrying dead tokens.
  const staleTokens = tokenRows
    .filter((_, i) => !results[i].ok && (results[i].status === 404 || results[i].status === 400))
    .map((row) => row.token as string);
  if (staleTokens.length > 0) {
    await adminClient
      .from("user_fcm_tokens")
      .delete()
      .eq("user_id", userId)
      .in("token", staleTokens);
  }

  return jsonResponse({ sent, total: tokenRows.length, prunedStale: staleTokens.length }, 200);
});

async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encoder = new TextEncoder();
  const headerB64 = base64url(encoder.encode(JSON.stringify(header)));
  const claimsB64 = base64url(encoder.encode(JSON.stringify(claims)));
  const signingInput = `${headerB64}.${claimsB64}`;

  const pemContents = serviceAccount.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(signingInput),
  );

  const jwt = `${signingInput}.${base64url(new Uint8Array(signature))}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const tokenJson = await tokenRes.json();
  if (!tokenRes.ok) {
    throw new Error(`Google token exchange failed: ${JSON.stringify(tokenJson)}`);
  }
  return tokenJson.access_token as string;
}

async function sendToToken(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: { token, notification: { title, body } },
      }),
    },
  );
  return { ok: res.ok, status: res.status };
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
