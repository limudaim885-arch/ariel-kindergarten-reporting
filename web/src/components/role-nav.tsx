"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export type NavLink = { href: string; label: string; count?: number; countLabel?: string };

/** The main menu of a role area. The first link is the area's home and matches only exactly. */
export function RoleNav({ label, links }: { label: string; links: readonly NavLink[] }) {
  const pathname = usePathname();
  return (
    <nav aria-label={label} className="order-last w-full sm:order-none sm:w-auto">
      <ul className="flex gap-1">
        {links.map((link, i) => {
          const active = i === 0 ? pathname === link.href : pathname.startsWith(link.href);
          return (
            <li key={link.href} className="flex-1 sm:flex-none">
              <Link
                href={link.href}
                aria-current={active ? "page" : undefined}
                className={`block whitespace-nowrap rounded-[10px] px-3 py-2 text-center text-sm font-medium ${
                  active ? "bg-accent-soft text-accent" : "text-ink hover:bg-surface-2"
                }`}
              >
                {link.label}
                {link.count ? (
                  <span className="ms-1.5 inline-block min-w-5 rounded-full bg-accent px-1.5 text-xs font-semibold text-on-fill">
                    {link.count}
                    {link.countLabel ? <span className="sr-only"> {link.countLabel}</span> : null}
                  </span>
                ) : null}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
