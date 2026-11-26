"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getAppUser, getAuthUser } from "@/lib/auth/session";
import { allow } from "@/lib/rate-limit";
import { createAdminClient } from "@/lib/supabase/admin";
import type { DecideInput } from "@/lib/staff/types";

const MSG = {
  session: "פג תוקף הכניסה. יש להתחבר מחדש ולנסות שוב.",
  forbidden: "אין לך הרשאה לבצע את הפעולה הזו.",
  invalid: "הנתונים שנשלחו לא תקינים. יש לרענן את הדף ולנסות שוב.",
  tooMany: "בוצעו יותר מדי פעולות. יש לנסות שוב בעוד כמה דקות.",
  failed: "השמירה נכשלה. שום דבר לא השתנה. יש לנסות שוב.",
} as const;

function logError(where: string, err: unknown) {
  // Never log names, comments or anything that identifies a person.
  console.error(`[staff] ${where}:`, err instanceof Error ? err.message : "unknown error");
}

/**
 * Final approval and lock, or return to the supplier. The database checks the
 * staff role, that the teacher approved, and that the report did not change
 * since she did.
 */
export async function decideStaffReport(input: DecideInput): Promise<{ ok: false; message: string }> {
  const [user, authUser] = await Promise.all([getAppUser(), getAuthUser()]);
  if (!user || !authUser || user.user_type !== "STAFF") return { ok: false, message: MSG.session };

  const { reportId, decision, reasonId, comment, confirmed } = (input ?? {}) as Partial<DecideInput>;
  if (
    typeof reportId !== "number" || !Number.isInteger(reportId) || reportId <= 0 ||
    (decision !== "APPROVE" && decision !== "RETURN") ||
    (reasonId !== null && (typeof reasonId !== "number" || !Number.isInteger(reasonId) || reasonId <= 0 || reasonId > 32767)) ||
    typeof comment !== "string" || comment.length > 450 ||
    typeof confirmed !== "boolean" ||
    (decision === "APPROVE" && !confirmed)
  ) {
    return { ok: false, message: MSG.invalid };
  }
  if (!(await allow("staffDecision"))) return { ok: false, message: MSG.tooMany };

  try {
    const { data, error } = await createAdminClient(`STAFF:${user.user_id}`)
      .schema("access")
      .rpc("staff_decide", {
        p_auth_user_id: authUser.id,
        p_report_id: reportId,
        p_decision: decision,
        p_reason_id: decision === "RETURN" ? reasonId : null,
        p_comment: decision === "RETURN" ? comment : null,
      });

    if (error) {
      logError("staff_decide", error);
      if (error.code === "42501") return { ok: false, message: MSG.forbidden };
      if (error.code === "22023") return { ok: false, message: MSG.invalid };
      return { ok: false, message: MSG.failed };
    }
    const result = data as { ok: true; status: string } | { ok: false; message: string };
    if (!result.ok) return { ok: false, message: result.message };
  } catch (err) {
    logError("decideStaffReport", err);
    return { ok: false, message: MSG.failed };
  }

  revalidatePath("/staff", "layout");
  redirect(`/staff/queue?done=${decision === "APPROVE" ? "locked" : "returned"}`);
}
