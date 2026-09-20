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

// Reads the role claim from an authorization JWT.
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

// Sends push notifications for authorized service requests.
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

// Obtains a Google OAuth access token for the service account.
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

// Sends a push notification to an FCM device token.
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

// Encodes bytes as a URL-safe Base64 string.
function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Creates a JSON response with CORS headers.
function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
