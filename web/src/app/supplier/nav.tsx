"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
  { href: "/supplier", label: "בית" },
  { href: "/supplier/new", label: "דיווח חדש" },
  { href: "/supplier/reports", label: "הדיווחים שלי" },
] as const;

export function SupplierNav() {
  const pathname = usePathname();
  return (
    <nav aria-label="תפריט ספק" className="order-last w-full sm:order-none sm:w-auto">
      <ul className="flex gap-1">
        {LINKS.map((link) => {
          const active =
            link.href === "/supplier" ? pathname === "/supplier" : pathname.startsWith(link.href);
          return (
            <li key={link.href} className="flex-1 sm:flex-none">
              <Link
                href={link.href}
                aria-current={active ? "page" : undefined}
                className={`block rounded-[10px] px-3 py-2 text-center text-sm font-medium ${
                  active ? "bg-accent-soft text-accent" : "text-ink hover:bg-surface-2"
                }`}
              >
                {link.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
