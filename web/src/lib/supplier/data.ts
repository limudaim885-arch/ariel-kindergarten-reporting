import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { getAuthUser, requireAppUser } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import type { SupplierData } from "./types";

/**
 * Everything the supplier screens show, for the signed-in supplier only.
 * The database picks the supplier by the session's auth user, never by an id
 * from the browser (access.supplier_data, migration 13).
 */
export const getSupplierData = cache(async (): Promise<SupplierData> => {
  await requireAppUser("SUPPLIER_CONTACT");
  const authUser = await getAuthUser();
  if (!authUser) redirect("/login");

  const { data, error } = await createAdminClient()
    .schema("access")
    .rpc("supplier_data", { p_auth_user_id: authUser.id });
  if (error) throw new Error(`access.supplier_data: ${error.message}`);
  return data as SupplierData;
});
