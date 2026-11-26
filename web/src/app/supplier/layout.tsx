import { connection } from "next/server";
import { RoleLayout } from "@/components/role-layout";
import { requireAppUser } from "@/lib/auth/session";

const LINKS = [
  { href: "/supplier", label: "בית" },
  { href: "/supplier/new", label: "דיווח חדש" },
  { href: "/supplier/reports", label: "הדיווחים שלי" },
] as const;

export default async function SupplierLayout({ children }: LayoutProps<"/supplier">) {
  await connection();
  const user = await requireAppUser("SUPPLIER_CONTACT");
  return (
    <RoleLayout userName={user.full_name} navLabel="תפריט ספק" links={LINKS}>
      {children}
    </RoleLayout>
  );
}
