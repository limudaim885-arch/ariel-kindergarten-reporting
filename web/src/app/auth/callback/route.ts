import { NextResponse, type NextRequest } from "next/server";
import { appUser } from "@/lib/auth/access";
import { HOME_BY_TYPE } from "@/lib/auth/session";
import { backToLogin, logSso } from "@/lib/auth/staff-sso";
import { allow } from "@/lib/rate-limit";
import { createSessionClient } from "@/lib/supabase/server";

// Step 2 of the staff sign-in: Microsoft (through Supabase) sends the browser
// back here with a one-time code. Only an active staff member in
// core.staff_users gets a session; anyone else is signed out again.
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;

  // Microsoft or Supabase refused, for example an account that was never
  // opened in the system ("Signups not allowed").
  const providerError = params.get("error");
  if (providerError) {
    logSso("provider", `${providerError}: ${params.get("error_description") ?? ""}`);
    return backToLogin(request, "denied");
  }

  const code = params.get("code");
  if (!code || code.length > 512) return backToLogin(request, "failed");
  if (!(await allow("staffSso"))) return backToLogin(request, "busy");

  let signedIn = false;
  try {
    const supabase = await createSessionClient();
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);
    if (error || !data.user) {
      logSso("exchangeCodeForSession", error ?? "no user");
    } else {
      const user = await appUser(data.user.id);
      if (user?.user_type === "STAFF") {
        signedIn = true;
      } else {
        await supabase.auth.signOut();
      }
    }
  } catch (err) {
    logSso("callback", err);
  }

  if (!signedIn) return backToLogin(request, "denied");
  return NextResponse.redirect(new URL(HOME_BY_TYPE.STAFF, request.url), 303);
}
