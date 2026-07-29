// Deno edge function: only a caller whose profile role is 'admin' may use
// this to create a new student or staff account. The service role key never
// leaves this server-side function.
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "Invalid session" }, 401);
  }

  const { data: callerProfile, error: profileError } = await callerClient
    .from("profiles")
    .select("role")
    .eq("id", userData.user.id)
    .single();

  if (profileError || callerProfile?.role !== "admin") {
    return jsonResponse({ error: "Only admins can create accounts" }, 403);
  }

  let body: {
    email?: string;
    password?: string;
    name?: string;
    campusId?: string;
    role?: string;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const { email, password, name, campusId, role } = body;
  if (
    !email ||
    !password ||
    !name ||
    !campusId ||
    (role !== "student" && role !== "staff")
  ) {
    return jsonResponse({ error: "Invalid request body" }, 400);
  }
  if (password.length < 8) {
    return jsonResponse({ error: "Password must be at least 8 characters" }, 400);
  }

  // Mirrors the profiles_campus_id_format check constraint: students use
  // 2-digit enrolment year + 5-digit index (7 digits), staff use a 4-digit ID.
  const campusIdPattern = role === "student" ? /^[0-9]{7}$/ : /^[0-9]{4}$/;
  if (!campusIdPattern.test(campusId)) {
    const example = role === "student" ? "2408009" : "1234";
    return jsonResponse(
      { error: `Invalid campus ID format for ${role}. Expected e.g. "${example}".` },
      400,
    );
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name, campus_id: campusId, role },
  });

  if (createError) {
    return jsonResponse({ error: createError.message }, 400);
  }

  return jsonResponse({ userId: created.user?.id }, 200);
});

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
