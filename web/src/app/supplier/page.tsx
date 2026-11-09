import { connection } from "next/server";
import { LandingShell } from "@/components/landing-shell";
import { requireAppUser } from "@/lib/auth/session";

export default async function Page() {
  await connection();
  const user = await requireAppUser("SUPPLIER_CONTACT");
  return <LandingShell user={user} heading="אזור ספק" />;
}
