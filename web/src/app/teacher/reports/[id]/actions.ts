"use server";

import { revalidatePath } from "next/cache";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { getAppUser, getAuthUser } from "@/lib/auth/session";
import { allow, clientIp } from "@/lib/rate-limit";
import { createAdminClient } from "@/lib/supabase/admin";
import { createSessionClient } from "@/lib/supabase/server";
import type { DecideInput } from "@/lib/teacher/types";

const MSG = {
  session: "פג תוקף הכניסה. יש להתחבר מחדש ולנסות שוב.",
  invalid: "הנתונים שנשלחו לא תקינים. יש לרענן את הדף ולנסות שוב.",
  tooMany: "בוצעו יותר מדי פעולות. יש לנסות שוב בעוד כמה דקות.",
  failed: "השמירה נכשלה. שום דבר לא השתנה. יש לנסות שוב.",
} as const;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function logError(where: string, err: unknown) {
  // Never log names, comments or anything that identifies a person.
  console.error(`[teacher] ${where}:`, err instanceof Error ? err.message : "unknown error");
}

/**
 * Approve or return a report. Approval needs only the "אני מאשרת" checkbox. The database checks that the report is in
 * one of this teacher's kindergartens and still waits for a signature, and
 * saves the evidence: phone, session, IP, user agent and a content hash.
 */
export async function decideReport(input: DecideInput): Promise<{ ok: false; message: string }> {
  const [user, authUser] = await Promise.all([getAppUser(), getAuthUser()]);
  if (!user || !authUser || user.user_type !== "TEACHER") return { ok: false, message: MSG.session };

  const { reportId, decision, reasonId, comment, confirmed } = (input ?? {}) as Partial<DecideInput>;
  if (
    typeof reportId !== "number" || !Number.isInteger(reportId) || reportId <= 0 ||
    (decision !== "APPROVED" && decision !== "REJECTED") ||
    (reasonId !== null && (typeof reasonId !== "number" || !Number.isInteger(reasonId) || reasonId <= 0 || reasonId > 32767)) ||
    typeof comment !== "string" || comment.length > 450 ||
    typeof confirmed !== "boolean" ||
    (decision === "APPROVED" && !confirmed)
  ) {
    return { ok: false, message: MSG.invalid };
  }
  if (!(await allow("teacherDecision"))) return { ok: false, message: MSG.tooMany };

  let sessionId: string | null = null;
  try {
    const { data } = await (await createSessionClient()).auth.getClaims();
    const claim = data?.claims?.session_id;
    sessionId = typeof claim === "string" && UUID_PATTERN.test(claim) ? claim : null;
  } catch (err) {
    logError("getClaims", err);
  }
  const userAgent = (await headers()).get("user-agent")?.slice(0, 400) ?? null;
  const ip = (await clientIp()).slice(0, 45);

  try {
    const { data, error } = await createAdminClient(`TEACHER:${user.user_id}`)
      .schema("access")
      .rpc("teacher_decide", {
        p_auth_user_id: authUser.id,
        p_report_id: reportId,
        p_decision: decision,
        p_reason_id: decision === "REJECTED" ? reasonId : null,
        p_comment: decision === "REJECTED" ? comment : null,
        p_signed_name: null,
        p_session_id: sessionId,
        p_ip: ip === "unknown" ? null : ip,
        p_user_agent: userAgent,
      });

    if (error) {
      logError("teacher_decide", error);
      if (error.code === "42501") return { ok: false, message: MSG.session };
      if (error.code === "22023") return { ok: false, message: MSG.invalid };
      return { ok: false, message: MSG.failed };
    }
    const result = data as { ok: true; status: string } | { ok: false; message: string };
    if (!result.ok) return { ok: false, message: result.message };
  } catch (err) {
    logError("decideReport", err);
    return { ok: false, message: MSG.failed };
  }

  revalidatePath("/teacher", "layout");
  redirect(`/teacher?done=${decision === "APPROVED" ? "approved" : "returned"}`);
}
