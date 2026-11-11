import type { ReactNode } from "react";

export function Card({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex min-h-[26rem] flex-col rounded-[18px] border border-line bg-surface p-6 shadow-card">
      <h2 className="mb-3 text-center text-[1.12rem] font-semibold text-ink">{title}</h2>
      {children}
    </section>
  );
}

export function Message({ kind, id, children }: { kind: "error" | "info"; id: string; children: ReactNode }) {
  const isError = kind === "error";
  return (
    <p
      id={id}
      role={isError ? "alert" : "status"}
      className={
        isError
          ? "mb-3 rounded-lg bg-critical-soft px-3 py-2 text-sm font-medium text-critical"
          : "mb-3 rounded-lg bg-success-soft px-3 py-2 text-sm font-medium text-success"
      }
    >
      {children}
    </p>
  );
}

export function Field({
  id,
  label,
  hint,
  children,
}: {
  id: string;
  label: string;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <div className="mb-3">
      <label htmlFor={id} className="mb-1 block text-sm font-medium text-ink">
        {label}
      </label>
      {children}
      {hint ? <p className="mt-1 text-sm text-ink-muted">{hint}</p> : null}
    </div>
  );
}

export const inputClass =
  "w-full rounded-[10px] border border-field-border bg-surface px-3 py-2.5 text-base text-ink placeholder:text-ink-muted";

export const otpInputClass = `${inputClass} text-center text-xl font-semibold tracking-[0.45em] [direction:ltr] tabular-nums`;

export function PrimaryButton({
  children,
  disabled,
}: {
  children: ReactNode;
  disabled?: boolean;
}) {
  return (
    <button
      type="submit"
      disabled={disabled}
      className="w-full rounded-[10px] bg-accent px-4 py-3 text-base font-semibold text-on-fill hover:bg-accent-strong disabled:opacity-60"
    >
      {children}
    </button>
  );
}

export function LinkButton({
  children,
  onClick,
  disabled,
}: {
  children: ReactNode;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="text-sm font-medium text-accent underline underline-offset-2 disabled:no-underline disabled:opacity-60"
    >
      {children}
    </button>
  );
}
