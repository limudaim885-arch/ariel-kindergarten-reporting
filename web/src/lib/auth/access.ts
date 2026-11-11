import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

export type UserType = "SUPPLIER_CONTACT" | "TEACHER";

export type LoginOption = { option_id: number; masked_phone: string };

export type AppUser = {
  user_type: "SUPPLIER_CONTACT" | "TEACHER" | "STAFF";
  user_id: number;
  full_name: string;
  scope_type: string;
  scope_id: number | null;
  scope_code: string | null;
  role_code: string | null;
};

export type FailedAttempt = { code_exhausted: boolean; locked_until: string | null };

export type VerifyStatus = "OK" | "LOCKED" | "CODE_EXHAUSTED";

// Thin wrappers over the access.* functions (service_role only, server only).
// Phone numbers returned by resolveLoginPhone must never reach the browser.
const access = () => createAdminClient().schema("access");

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await access().rpc(fn, args);
  if (error) throw new Error(`access.${fn}: ${error.message}`);
  return data as T;
}

export async function loginOptions(userType: UserType, loginKey: string) {
  return (await rpc<LoginOption[] | null>("login_options", {
    p_user_type: userType,
    p_login_key: loginKey,
  })) ?? [];
}

export function resolveLoginPhone(userType: UserType, loginKey: string, optionId: number) {
  return rpc<string | null>("resolve_login_phone", {
    p_user_type: userType,
    p_login_key: loginKey,
    p_option_id: optionId,
  });
}

export const canSendOtp = (phone: string) => rpc<boolean>("can_send_otp", { p_phone: phone });

export const registerOtpSent = (phone: string, userType: UserType, optionId: number) =>
  rpc<number>("register_otp_sent", {
    p_phone: phone,
    p_recipient_type: userType,
    p_recipient_id: optionId,
  });

export const verifyStatus = (phone: string) => rpc<VerifyStatus>("verify_status", { p_phone: phone });

export const registerFailedAttempt = (phone: string) =>
  rpc<FailedAttempt>("register_failed_attempt", { p_phone: phone });

export const resetFailedAttempts = (phone: string) =>
  rpc<null>("reset_failed_attempts", { p_phone: phone });

export async function appUsers(authUserId: string): Promise<AppUser[]> {
  return (await rpc<AppUser[] | null>("app_user", { p_auth_user_id: authUserId })) ?? [];
}

// A teacher assigned to several kindergartens gets one row per kindergarten.
export async function appUser(authUserId: string): Promise<AppUser | null> {
  return (await appUsers(authUserId))[0] ?? null;
}
