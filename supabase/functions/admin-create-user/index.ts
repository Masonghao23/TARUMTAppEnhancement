import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Creates student or staff accounts for authenticated admins.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

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
    courseIds?: string[];
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const { email, password, name, campusId, role, courseIds } = body;
  if (
    !email ||
    !password ||
    !name ||
    !campusId ||
    (role !== "student" && role !== "staff")
  ) {
    return jsonResponse({ error: "Invalid request body" }, 400);
  }
  if (
    courseIds !== undefined &&
    (!Array.isArray(courseIds) || courseIds.some((id) => typeof id !== "string"))
  ) {
    return jsonResponse({ error: "courseIds must be an array of strings" }, 400);
  }
  if (password.length < 8) {
    return jsonResponse({ error: "Password must be at least 8 characters" }, 400);
  }

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

  const userId = created.user?.id;

  if (role === "student" && courseIds && courseIds.length > 0 && userId) {
    const { error: enrollError } = await adminClient
      .from("course_enrollments")
      .insert(courseIds.map((courseId) => ({ student_id: userId, course_id: courseId })));

    if (enrollError) {
      return jsonResponse(
        { userId, enrollmentWarning: enrollError.message },
        200,
      );
    }
  }

  return jsonResponse({ userId }, 200);
});

// Creates a JSON response with CORS headers.
function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
