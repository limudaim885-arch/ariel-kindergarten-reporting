import "server-only";
import { NextResponse, type NextRequest } from "next/server";
import { getAppUser } from "@/lib/auth/session";
import { allow } from "@/lib/rate-limit";

/**
 * First check of every staff Excel download (Route Handlers have no layout).
 * Returns a response to send instead, or null to go on. The database functions
 * check the staff member again.
 */
export async function staffExportGate(request: NextRequest): Promise<Response | null> {
  const user = await getAppUser();
  if (!user) return NextResponse.redirect(new URL("/login", request.url), 303);
  if (user.user_type !== "STAFF") return new Response("אין הרשאה", { status: 403 });
  if (!(await allow("excelExport"))) {
    return new Response("בוצעו יותר מדי הורדות. יש לנסות שוב בעוד כמה דקות.", { status: 429 });
  }
  return null;
}
