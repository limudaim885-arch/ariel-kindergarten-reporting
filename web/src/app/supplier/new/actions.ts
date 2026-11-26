"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getAppUser, getAuthUser } from "@/lib/auth/session";
import { allow } from "@/lib/rate-limit";
import { createAdminClient } from "@/lib/supabase/admin";
import type { SubmitItem, SubmitResult } from "@/lib/supplier/types";

const MSG = {
  session: "פג תוקף הכניסה. יש להתחבר מחדש ולשלוח שוב.",
  invalid: "הנתונים שנשלחו לא תקינים. יש לרענן את הדף ולנסות שוב.",
  tooMany: "בוצעו יותר מדי ניסיונות שליחה. יש לנסות שוב בעוד כמה דקות.",
  failed: "השליחה נכשלה. שום דיווח לא נשלח. יש לנסות שוב.",
} as const;

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

type CleanItem = { engagement_id: number; lines: { date: string; double: boolean }[] };

/** Strict shape check. The database checks the business rules again. */
function cleanItems(input: unknown): CleanItem[] | null {
  if (!Array.isArray(input) || input.length < 1 || input.length > 50) return null;
  const engagements = new Set<number>();
  const out: CleanItem[] = [];

  for (const item of input) {
    if (!item || typeof item !== "object") return null;
    const { engagementId, lines } = item as Record<string, unknown>;
    if (typeof engagementId !== "number" || !Number.isInteger(engagementId) || engagementId <= 0) return null;
    if (engagements.has(engagementId)) return null;
    if (!Array.isArray(lines) || lines.length < 1 || lines.length > 62) return null;

    const dates = new Set<string>();
    const cleanLines: CleanItem["lines"] = [];
    for (const line of lines) {
      if (!line || typeof line !== "object") return null;
      const { date, double } = line as Record<string, unknown>;
      if (typeof date !== "string" || !DATE_PATTERN.test(date) || dates.has(date)) return null;
      if (typeof double !== "boolean") return null;
      dates.add(date);
      cleanLines.push({ date, double });
    }
    engagements.add(engagementId);
    out.push({ engagement_id: engagementId, lines: cleanLines });
  }
  return out;
}

function logError(where: string, err: unknown) {
  // Never log the submitted dates or anything that identifies a person.
  console.error(`[supplier] ${where}:`, err instanceof Error ? err.message : "unknown error");
}

/**
 * Sends the selected dates to the teachers. All or nothing: if any garden has a
 * problem, nothing is written and the problems come back per garden.
 * On success the browser goes to "My reports".
 */
export async function submitReport(input: SubmitItem[]): Promise<SubmitResult> {
  const [user, authUser] = await Promise.all([getAppUser(), getAuthUser()]);
  if (!user || !authUser || user.user_type !== "SUPPLIER_CONTACT") return { ok: false, message: MSG.session };

  const items = cleanItems(input);
  if (!items) return { ok: false, message: MSG.invalid };
  if (!(await allow("submitReport"))) return { ok: false, message: MSG.tooMany };

  let sent: number;
  try {
    const { data, error } = await createAdminClient(`SUPPLIER_CONTACT:${user.user_id}`)
      .schema("access")
      .rpc("supplier_submit", { p_auth_user_id: authUser.id, p_items: items });

    if (error) {
      logError("supplier_submit", error);
      if (error.code === "42501") return { ok: false, message: MSG.session };
      if (error.code === "22023") return { ok: false, message: MSG.invalid };
      return { ok: false, message: MSG.failed };
    }

    const result = data as
      | { ok: true; reports: unknown[] }
      | { ok: false; errors: { engagement_id: number; message: string }[] };
    if (!result.ok) {
      return {
        ok: false,
        errors: result.errors.map((e) => ({ engagementId: e.engagement_id, message: e.message })),
      };
    }
    sent = result.reports.length;
  } catch (err) {
    logError("submitReport", err);
    return { ok: false, message: MSG.failed };
  }

  revalidatePath("/supplier", "layout");
  redirect(`/supplier/reports?sent=${sent}`);
}
