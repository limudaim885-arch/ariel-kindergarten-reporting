import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { getAuthUser, requireAppUser } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import type { StaffCapsData, StaffMetricsData, StaffMonthlyData, StaffReportData, StaffReportsData } from "./types";

/**
 * Staff data from the access.staff_* functions (migration 16). The database
 * picks the staff member by the session's auth user, never by an id from the
 * browser, and decides what that role may do.
 */
async function staffAuthId(): Promise<string> {
  await requireAppUser("STAFF");
  const authUser = await getAuthUser();
  if (!authUser) redirect("/login");
  return authUser.id;
}

export const getStaffReports = cache(async (): Promise<StaffReportsData> => {
  const id = await staffAuthId();
  const { data, error } = await createAdminClient().schema("access").rpc("staff_reports", { p_auth_user_id: id });
  if (error) throw new Error(`access.staff_reports: ${error.message}`);
  return data as StaffReportsData;
});

/** One report in full, or null when there is no such report. */
export const getStaffReport = cache(async (reportId: number): Promise<StaffReportData | null> => {
  const id = await staffAuthId();
  const { data, error } = await createAdminClient()
    .schema("access")
    .rpc("staff_report", { p_auth_user_id: id, p_report_id: reportId });
  if (error) {
    if (error.code === "22023") return null;
    throw new Error(`access.staff_report: ${error.message}`);
  }
  return data as StaffReportData;
});

export const getStaffCaps = cache(async (): Promise<StaffCapsData> => {
  const id = await staffAuthId();
  const { data, error } = await createAdminClient().schema("access").rpc("staff_caps", { p_auth_user_id: id });
  if (error) throw new Error(`access.staff_caps: ${error.message}`);
  return data as StaffCapsData;
});

export const getStaffMonthly = cache(async (year: number, month: number): Promise<StaffMonthlyData> => {
  const id = await staffAuthId();
  const { data, error } = await createAdminClient()
    .schema("access")
    .rpc("staff_monthly", { p_auth_user_id: id, p_year: year, p_month: month });
  if (error) throw new Error(`access.staff_monthly: ${error.message}`);
  return data as StaffMonthlyData;
});

export const getStaffMetrics = cache(async (): Promise<StaffMetricsData> => {
  const id = await staffAuthId();
  const { data, error } = await createAdminClient().schema("access").rpc("staff_metrics", { p_auth_user_id: id });
  if (error) throw new Error(`access.staff_metrics: ${error.message}`);
  return data as StaffMetricsData;
});
