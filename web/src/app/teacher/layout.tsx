import { connection } from "next/server";
import { RoleLayout } from "@/components/role-layout";
import { requireAppUser } from "@/lib/auth/session";

const LINKS = [
  { href: "/teacher", label: "תיבת אישורים" },
  { href: "/teacher/history", label: "דיווחים שטופלו" },
] as const;

export default async function TeacherLayout({ children }: LayoutProps<"/teacher">) {
  await connection();
  const user = await requireAppUser("TEACHER");
  return (
    <RoleLayout userName={user.full_name} navLabel="תפריט גננת" links={LINKS}>
      {children}
    </RoleLayout>
  );
}
