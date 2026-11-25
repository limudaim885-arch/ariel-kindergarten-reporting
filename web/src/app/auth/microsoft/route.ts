import { NextResponse, type NextRequest } from "next/server";
import { env } from "@/lib/env";
import { backToLogin, logSso, SSO_CALLBACK_PATH } from "@/lib/auth/staff-sso";
import { allow } from "@/lib/rate-limit";
import { createSessionClient } from "@/lib/supabase/server";

/**
 * signInWithOAuth only builds a URL, so if the Azure provider is off in
 * Supabase the user would land on a raw error page there. Ask Supabase first
 * (public settings endpoint, anon key) and stay on our login page if it is off.
 */
async function azureEnabled(): Promise<boolean> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/settings`, {
    headers: { apikey: env.supabaseAnonKey },
    cache: "no-store",
    signal: AbortSignal.timeout(5_000),
  });
  if (!res.ok) return false;
  const body = (await res.json()) as { external?: Record<string, unknown> };
  return body.external?.azure === true;
}

// Step 1 of the staff sign-in: send the browser to Microsoft (through Supabase).
// The PKCE verifier is kept in a cookie by the Supabase client and checked in
// /auth/callback, so a code taken from another browser cannot be used.
export async function GET(request: NextRequest) {
  if (!(await allow("staffSso"))) return backToLogin(request, "busy");

  let target: string | null = null;
  try {
    if (!(await azureEnabled())) {
      logSso("settings", "azure provider is not enabled");
      return backToLogin(request, "failed");
    }
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
