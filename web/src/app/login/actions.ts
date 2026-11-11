"use server";

import { redirect } from "next/navigation";
import { createSessionClient } from "@/lib/supabase/server";
import {
  appUser,
  appUsers,
  canSendOtp,
  loginOptions,
  registerFailedAttempt,
  registerOtpSent,
  resetFailedAttempts,
  resolveLoginPhone,
  verifyStatus,
} from "@/lib/auth/access";
import { HOME_BY_TYPE } from "@/lib/auth/session";
import { allow } from "@/lib/rate-limit";
import type { ActionResult, PhoneOption, PhoneUserType } from "./types";

// Messages are deliberately generic so they do not reveal whether a supplier,
// kindergarten, phone or email exists.
const MSG = {
  generic: "פרטים שגויים",
  tooMany: "בוצעו יותר מדי ניסיונות. יש לנסות שוב בעוד כמה דקות.",
  cannotSend: "לא ניתן לשלוח קוד כעת. יש לנסות שוב מאוחר יותר.",
  sendFailed: "שליחת הקוד נכשלה. יש לנסות שוב מאוחר יותר.",
  cannotContinue: "לא ניתן להמשיך כעת. יש לנסות שוב מאוחר יותר.",
  exhausted: "הקוד נפסל אחרי מספר ניסיונות שגויים. יש לבקש קוד חדש.",
  wrongCode: "הקוד שגוי או שפג תוקפו.",
  failed: "אירעה תקלה. יש לנסות שוב.",
} as const;

const USER_TYPES: readonly PhoneUserType[] = ["SUPPLIER_CONTACT", "TEACHER"];
const KEY_PATTERN = /^\d{1,10}$/;
const CODE_PATTERN = /^\d{6}$/;
// Allowlist, not just structure: letters, digits and the usual address symbols only.
const EMAIL_PATTERN = /^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/;

type PhoneInput = { userType: PhoneUserType; loginKey: string; optionId: number };

function cleanPhoneInput(input: PhoneInput): PhoneInput | null {
  const loginKey = String(input.loginKey ?? "").trim();
  if (!USER_TYPES.includes(input.userType)) return null;
  if (!KEY_PATTERN.test(loginKey)) return null;
  if (!Number.isInteger(input.optionId) || input.optionId <= 0) return null;
  return { userType: input.userType, loginKey, optionId: input.optionId };
}

function logError(where: string, err: unknown) {
  // Never log phone numbers, codes or emails.
  console.error(`[login] ${where}:`, err instanceof Error ? err.message : "unknown error");
}

/** Step 1: supplier number / kindergarten code -> masked phones only. */
export async function lookupOptions(
  userType: PhoneUserType,
  loginKey: string,
): Promise<ActionResult<{ options: PhoneOption[] }>> {
  const key = String(loginKey ?? "").trim();
  if (!USER_TYPES.includes(userType) || !KEY_PATTERN.test(key)) {
    return { ok: false, message: MSG.generic };
  }
  if (!(await allow("lookupOptions"))) return { ok: false, message: MSG.tooMany };

  try {
    const rows = await loginOptions(userType, key);
    if (rows.length === 0) return { ok: false, message: MSG.generic };
    return {
      ok: true,
      options: rows.map((r) => ({ id: r.option_id, masked: r.masked_phone })),
    };
  } catch (err) {
    logError("lookupOptions", err);
    return { ok: false, message: MSG.failed };
  }
}

/** Step 2: send the SMS code to the chosen phone. The full phone stays on the server. */
export async function sendCode(input: PhoneInput): Promise<ActionResult> {
  const clean = cleanPhoneInput(input);
  if (!clean) return { ok: false, message: MSG.generic };
  if (!(await allow("sendCode"))) return { ok: false, message: MSG.tooMany };

  try {
    const phone = await resolveLoginPhone(clean.userType, clean.loginKey, clean.optionId);
    if (!phone) return { ok: false, message: MSG.generic };
    if (!(await canSendOtp(phone))) return { ok: false, message: MSG.cannotSend };

    const supabase = await createSessionClient();
    const { error } = await supabase.auth.signInWithOtp({
      phone,
      options: { shouldCreateUser: false },
    });
    if (error) {
      logError("signInWithOtp", error);
      return { ok: false, message: MSG.sendFailed };
    }
    await registerOtpSent(phone, clean.userType, clean.optionId);
    return { ok: true };
  } catch (err) {
    logError("sendCode", err);
    return { ok: false, message: MSG.sendFailed };
  }
}

/** Step 3: check the code, then load the user and start the session. */
export async function verifyCode(input: PhoneInput & { code: string }): Promise<ActionResult> {
  const clean = cleanPhoneInput(input);
  const code = String(input.code ?? "").replace(/\s/g, "");
  if (!clean || !CODE_PATTERN.test(code)) return { ok: false, message: MSG.wrongCode };
  if (!(await allow("verifyCode"))) return { ok: false, message: MSG.tooMany };

  let home: string;
  try {
    const phone = await resolveLoginPhone(clean.userType, clean.loginKey, clean.optionId);
    if (!phone) return { ok: false, message: MSG.generic };

    const status = await verifyStatus(phone);
    if (status === "LOCKED") return { ok: false, message: MSG.cannotContinue };
    if (status === "CODE_EXHAUSTED") return { ok: false, message: MSG.exhausted, exhausted: true };

    const supabase = await createSessionClient();
    const { data, error } = await supabase.auth.verifyOtp({ phone, token: code, type: "sms" });
    if (error || !data.user) {
      const failed = await registerFailedAttempt(phone);
      if (failed.locked_until) return { ok: false, message: MSG.cannotContinue };
      if (failed.code_exhausted) return { ok: false, message: MSG.exhausted, exhausted: true };
      return { ok: false, message: MSG.wrongCode };
    }

    await resetFailedAttempts(phone);

    // The session must belong to exactly the person who was selected.
    const rows = await appUsers(data.user.id);
    const user = rows.find(
      (u) =>
        u.user_type === clean.userType &&
        u.user_id === clean.optionId &&
        u.scope_code === clean.loginKey,
    );
    if (!user) {
      await supabase.auth.signOut();
      return { ok: false, message: MSG.generic };
    }
    home = HOME_BY_TYPE[user.user_type];
  } catch (err) {
    logError("verifyCode", err);
    return { ok: false, message: MSG.failed };
  }
  redirect(home);
}

/** Staff: send a code to the email. The answer never says whether the address is registered. */
export async function staffSendCode(email: string): Promise<ActionResult> {
  const address = String(email ?? "").trim().toLowerCase();
  if (address.length > 254 || !EMAIL_PATTERN.test(address)) {
    return { ok: false, message: MSG.generic };
  }
  if (!(await allow("staffSend"))) return { ok: false, message: MSG.tooMany };

  try {
    const supabase = await createSessionClient();
    const { error } = await supabase.auth.signInWithOtp({
      email: address,
      options: { shouldCreateUser: false },
    });
    if (error) logError("staff signInWithOtp", error);
  } catch (err) {
    logError("staffSendCode", err);
  }
  return { ok: true };
}

export async function staffVerifyCode(email: string, token: string): Promise<ActionResult> {
  const address = String(email ?? "").trim().toLowerCase();
  const code = String(token ?? "").replace(/\s/g, "");
  if (!EMAIL_PATTERN.test(address) || !CODE_PATTERN.test(code)) {
    return { ok: false, message: MSG.wrongCode };
  }
  if (!(await allow("staffVerify"))) return { ok: false, message: MSG.tooMany };

  try {
    const supabase = await createSessionClient();
    const { data, error } = await supabase.auth.verifyOtp({
      email: address,
      token: code,
      type: "email",
    });
    if (error || !data.user) return { ok: false, message: MSG.wrongCode };

    const user = await appUser(data.user.id);
    if (!user || user.user_type !== "STAFF") {
      await supabase.auth.signOut();
      return { ok: false, message: MSG.wrongCode };
    }
  } catch (err) {
    logError("staffVerifyCode", err);
    return { ok: false, message: MSG.failed };
  }
  redirect(HOME_BY_TYPE.STAFF);
}
