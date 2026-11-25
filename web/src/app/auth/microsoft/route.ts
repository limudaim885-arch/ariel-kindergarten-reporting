import { NextResponse, type NextRequest } from "next/server";
import { backToLogin, logSso, SSO_CALLBACK_PATH } from "@/lib/auth/staff-sso";
import { allow } from "@/lib/rate-limit";
import { createSessionClient } from "@/lib/supabase/server";

// Step 1 of the staff sign-in: send the browser to Microsoft (through Supabase).
// The PKCE verifier is kept in a cookie by the Supabase client and checked in
// /auth/callback, so a code taken from another browser cannot be used.
export async function GET(request: NextRequest) {
  if (!(await allow("staffSso"))) return backToLogin(request, "busy");

  let target: string | null = null;
  try {
    const supabase = await createSessionClient();
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider: "azure",
      options: {
        redirectTo: new URL(SSO_CALLBACK_PATH, request.url).toString(),
        scopes: "email",
        skipBrowserRedirect: true,
      },
    });
    if (error) logSso("signInWithOAuth", error);
    else target = data.url;
  } catch (err) {
    logSso("signInWithOAuth", err);
  }

  if (!target) return backToLogin(request, "failed");
  return NextResponse.redirect(target, 303);
}
