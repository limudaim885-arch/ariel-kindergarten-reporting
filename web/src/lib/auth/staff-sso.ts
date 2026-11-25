import "server-only";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Staff sign in with their Ariel work account (Microsoft Entra ID, Supabase
 * "azure" provider). The browser only ever goes:
 *   /auth/microsoft -> Microsoft -> Supabase -> /auth/callback -> /staff
 * Who may enter is still decided by access.app_user, never by Microsoft alone.
 */
export const SSO_CALLBACK_PATH = "/auth/callback";

/** Reasons shown on the login page. Deliberately general. */
export type StaffLoginError = "denied" | "failed" | "busy";

export const STAFF_LOGIN_MESSAGES: Record<StaffLoginError, string> = {
  denied: "לא ניתן להתחבר עם החשבון הזה. אם את מצוות החברה העירונית ואין לך גישה, יש לפנות למנהל המערכת.",
  failed: "החיבור לחשבון אריאל נכשל. יש לנסות שוב.",
  busy: "בוצעו יותר מדי ניסיונות. יש לנסות שוב בעוד כמה דקות.",
};

export function isStaffLoginError(value: unknown): value is StaffLoginError {
  return typeof value === "string" && value in STAFF_LOGIN_MESSAGES;
}

/** Back to the login page with a general reason. 303 so the browser follows with GET. */
export function backToLogin(request: NextRequest, reason: StaffLoginError) {
  const url = new URL("/login", request.url);
  url.searchParams.set("staff", reason);
  return NextResponse.redirect(url, 303);
}

export function logSso(where: string, err: unknown) {
  // Never log codes, tokens or email addresses.
  const message =
    err instanceof Error ? err.message : typeof err === "string" ? err.slice(0, 200) : "unknown error";
  console.error(`[staff-sso] ${where}:`, message);
}
