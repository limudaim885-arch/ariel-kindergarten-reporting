"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getAppUser, getAuthUser } from "@/lib/auth/session";
import { allow } from "@/lib/rate-limit";
import { createAdminClient } from "@/lib/supabase/admin";
import type { CapOverrideInput } from "@/lib/staff/types";

const MSG = {
  session: "פג תוקף הכניסה. יש להתחבר מחדש ולנסות שוב.",
  forbidden: "אין לך הרשאה לבצע את הפעולה הזו.",
  invalid: "הנתונים שנשלחו לא תקינים. מספר המפגשים צריך להיות בין 0 ל-100, והסכום בין 0 ל-100,000 ₪.",
  tooMany: "בוצעו יותר מדי פעולות. יש לנסות שוב בעוד כמה דקות.",
  failed: "השמירה נכשלה. שום דבר לא השתנה. יש לנסות שוב.",
} as const;

function logError(where: string, err: unknown) {
  console.error(`[staff] ${where}:`, err instanceof Error ? err.message : "unknown error");
}

/** Approve a cap exception: extra sessions and/or amount for one engagement, with a reason. */
export async function addCapOverride(input: CapOverrideInput): Promise<{ ok: false; message: string }> {
  const [user, authUser] = await Promise.all([getAppUser(), getAuthUser()]);
  if (!user || !authUser || user.user_type !== "STAFF") return { ok: false, message: MSG.session };

  const { engagementId, extraSessions, extraAmount, reason } = (input ?? {}) as Partial<CapOverrideInput>;
  if (
    typeof engagementId !== "number" || !Number.isInteger(engagementId) || engagementId <= 0 ||
    typeof extraSessions !== "number" || !Number.isInteger(extraSessions) || extraSessions < 0 || extraSessions > 100 ||
    typeof extraAmount !== "number" || !Number.isFinite(extraAmount) || extraAmount < 0 || extraAmount > 100_000 ||
    typeof reason !== "string" || reason.length > 450
  ) {
    return { ok: false, message: MSG.invalid };
  }
  if (!(await allow("capOverride"))) return { ok: false, message: MSG.tooMany };

  try {
    const { data, error } = await createAdminClient(`STAFF:${user.user_id}`)
      .schema("access")
      .rpc("staff_add_cap_override", {
        p_auth_user_id: authUser.id,
        p_engagement_id: engagementId,
        p_extra_sessions: extraSessions,
        p_extra_amount: Math.round(extraAmount * 100) / 100,
        p_reason: reason,
      });
    if (error) {
      logError("staff_add_cap_override", error);
      if (error.code === "42501") return { ok: false, message: MSG.forbidden };
      if (error.code === "22023") return { ok: false, message: MSG.invalid };
      return { ok: false, message: MSG.failed };
    }
    const result = data as { ok: true } | { ok: false; message: string };
    if (!result.ok) return { ok: false, message: result.message };
  } catch (err) {
    logError("addCapOverride", err);
    return { ok: false, message: MSG.failed };
  }

  revalidatePath("/staff", "layout");
  redirect("/staff/caps?done=1");
}
