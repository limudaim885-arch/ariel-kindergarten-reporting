import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createSessionClient } from "@/lib/supabase/server";
import { appUser, type AppUser } from "@/lib/auth/access";

export const HOME_BY_TYPE: Record<AppUser["user_type"], string> = {
  SUPPLIER_CONTACT: "/supplier",
  TEACHER: "/teacher",
  STAFF: "/staff",
};

/** The Supabase Auth user of this request (validated with Supabase), or null. */
export const getAuthUser = cache(async (): Promise<User | null> => {
  const supabase = await createSessionClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
});

/**
 * The signed-in user as the database sees them (access.app_user), or null.
 * Permissions are always decided here, never from data sent by the browser.
 */
export const getAppUser = cache(async (): Promise<AppUser | null> => {
  const user = await getAuthUser();
  if (!user) return null;
  return appUser(user.id);
});

export async function requireAppUser(type: AppUser["user_type"]): Promise<AppUser> {
  const user = await getAppUser();
  if (!user) redirect("/login");
  if (user.user_type !== type) redirect(HOME_BY_TYPE[user.user_type]);
  return user;
}
