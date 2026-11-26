import { connection } from "next/server";
import { RoleLayout } from "@/components/role-layout";
import { requireAppUser } from "@/lib/auth/session";
import { getStaffReports } from "@/lib/staff/data";

export default async function StaffLayout({ children }: LayoutProps<"/staff">) {
  await connection();
  const user = await requireAppUser("STAFF");
  const { reports } = await getStaffReports();
  const queue = reports.filter((r) => r.status === "TEACHER_APPROVED").length;

  const links = [
    { href: "/staff", label: "ראשי" },
    { href: "/staff/queue", label: "אישורים", count: queue, countLabel: "ממתינים" },
    { href: "/staff/reports", label: "דיווחים" },
    { href: "/staff/caps", label: "תקרות" },
  ];

  return (
    <RoleLayout userName={user.full_name} navLabel="תפריט צוות" links={links}>
      {children}
    </RoleLayout>
  );
}
