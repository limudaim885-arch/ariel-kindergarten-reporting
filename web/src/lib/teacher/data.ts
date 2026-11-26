import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { getAuthUser, requireAppUser } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import type { TeacherData } from "./types";

/**
 * Everything the teacher screens show: only the kindergartens this teacher is
 * assigned to today (access.teacher_data, migration 14). The database picks the
 * teacher by the session's auth user, never by an id from the browser.
 */
export const getTeacherData = cache(async (): Promise<TeacherData> => {
  await requireAppUser("TEACHER");
  const authUser = await getAuthUser();
  if (!authUser) redirect("/login");

  const { data, error } = await createAdminClient()
    .schema("access")
    .rpc("teacher_data", { p_auth_user_id: authUser.id });
  if (error) throw new Error(`access.teacher_data: ${error.message}`);
  return data as TeacherData;
});
