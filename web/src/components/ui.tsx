import type { ReactNode } from "react";
import type { ReportStatus } from "@/lib/supplier/types";

// Shared building blocks for the role screens. No inline styles anywhere:
// the CSP blocks them (see lib/csp.ts).

export const buttonClass =
  "inline-flex items-center justify-center gap-2 rounded-[10px] bg-accent px-4 py-2.5 text-base font-semibold text-on-fill hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60";

export const secondaryButtonClass =
  "inline-flex items-center justify-center gap-2 rounded-[10px] border border-line-strong bg-surface px-3 py-2 text-sm font-medium text-ink hover:bg-surface-2 disabled:cursor-not-allowed disabled:opacity-60";

export function PageHead({ title, intro, action }: { title: string; intro?: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-2xl font-semibold text-ink">{title}</h1>
        {intro ? <p className="mt-1 text-ink-muted">{intro}</p> : null}
      </div>
      {action}
    </div>
  );
}

export function Panel({ title, children, className = "" }: { title?: string; children: ReactNode; className?: string }) {
  return (
    <section className={`mb-5 rounded-[18px] border border-line bg-surface p-5 shadow-card ${className}`}>
      {title ? <h2 className="mb-3 text-lg font-semibold text-ink">{title}</h2> : null}
      {children}
    </section>
  );
}

const CALLOUT: Record<"info" | "warning" | "critical" | "success", string> = {
  info: "bg-info-soft text-info",
  warning: "bg-warning-soft text-warning",
  critical: "bg-critical-soft text-critical",
  success: "bg-success-soft text-success",
};

export function Callout({
  kind = "info",
  role,
  children,
}: {
  kind?: keyof typeof CALLOUT;
  role?: "status" | "alert";
  children: ReactNode;
}) {
  return (
    <div role={role} className={`mb-4 rounded-xl px-4 py-3 ${CALLOUT[kind]}`}>
      {children}
    </div>
  );
}

const PILL: Record<ReportStatus | "NONE", string> = {
  NONE: "bg-surface-2 text-ink-muted",
  DRAFT: "bg-surface-2 text-ink-muted",
  SENT_TO_TEACHER: "bg-warning-soft text-warning",
  TEACHER_APPROVED: "bg-info-soft text-info",
  TEACHER_REJECTED: "bg-critical-soft text-critical",
  RETURNED: "bg-critical-soft text-critical",
  STAFF_APPROVED: "bg-success-soft text-success",
  LOCKED: "bg-success-soft text-success",
};

export function StatusPill({ status, label }: { status: ReportStatus | "NONE"; label: string }) {
  return (
    <span className={`inline-block whitespace-nowrap rounded-full px-2.5 py-0.5 text-sm font-medium ${PILL[status]}`}>
      {label}
    </span>
  );
}

export function StatCard({ title, value, sub, accent }: { title: string; value: ReactNode; sub?: ReactNode; accent?: boolean }) {
  return (
    <div
      className={`rounded-[18px] border p-4 shadow-card ${
        accent ? "border-accent bg-accent-soft" : "border-line bg-surface"
      }`}
    >
      <h2 className="text-sm font-medium text-ink-muted">{title}</h2>
      <div className="mt-1 text-3xl font-semibold tabular-nums text-ink">{value}</div>
      {sub ? <div className="mt-1 text-sm text-ink-muted">{sub}</div> : null}
    </div>
  );
}

/** A filled bar for used / cap. SVG attributes, not inline styles, so the CSP allows it. */
export function CapBar({ label, used, cap, text }: { label: string; used: number; cap: number; text: string }) {
  const pct = cap > 0 ? Math.min(100, Math.max(0, (used / cap) * 100)) : 100;
  const tone = used >= cap ? "fill-critical" : pct >= 80 ? "fill-warning" : "fill-accent";
  return (
    <div className="mb-2">
      <div className="mb-1 flex justify-between gap-2 text-sm">
        <span className="text-ink-muted">{label}</span>
        <span className="tabular-nums text-ink">{text}</span>
      </div>
      <svg
        viewBox="0 0 100 6"
        preserveAspectRatio="none"
        className="block h-2 w-full overflow-hidden rounded-full"
        role="img"
        aria-label={`${label}: ${text}`}
      >
        <rect x="0" y="0" width="100" height="6" className="fill-surface-2" />
        {/* RTL: the bar fills from the right */}
        <rect x={100 - pct} y="0" width={pct} height="6" className={tone} />
      </svg>
    </div>
  );
}
