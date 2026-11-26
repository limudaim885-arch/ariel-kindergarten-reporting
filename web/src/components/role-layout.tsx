import type { ReactNode } from "react";
import { signOut } from "@/lib/auth/actions";
import { RoleNav, type NavLink } from "./role-nav";

/** Header, menu and main area shared by the supplier, teacher and staff areas. */
export function RoleLayout({
  userName,
  navLabel,
  links,
  children,
}: {
  userName: string;
  navLabel: string;
  links: readonly NavLink[];
  children: ReactNode;
}) {
  return (
    <>
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:right-3 focus:top-3 focus:z-10 focus:rounded-lg focus:bg-surface focus:px-3 focus:py-2"
      >
        דילוג לתוכן
      </a>
      <header className="border-b border-line bg-surface">
        <div className="mx-auto flex w-full max-w-6xl flex-wrap items-center justify-between gap-x-6 gap-y-2 px-4 py-3">
          <div>
            <p className="font-semibold text-ink">דיווח הגנים</p>
            <p className="text-sm text-ink-muted">{userName}</p>
          </div>
          <RoleNav label={navLabel} links={links} />
          <form action={signOut}>
            <button
              type="submit"
              className="rounded-[10px] border border-line-strong px-3 py-1.5 text-sm font-medium text-ink hover:bg-surface-2"
            >
              יציאה
            </button>
          </form>
        </div>
      </header>
      <main id="main" className="mx-auto w-full max-w-6xl flex-1 px-4 py-6">
        {children}
      </main>
    </>
  );
}
