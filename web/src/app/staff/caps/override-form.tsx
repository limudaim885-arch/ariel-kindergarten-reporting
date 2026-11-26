"use client";

import { useId, useState, useTransition } from "react";
import { buttonClass } from "@/components/ui";
import { formatMoney } from "@/lib/format";
import { addCapOverride } from "./actions";

const fieldClass = "w-full rounded-[10px] border border-field-border bg-surface px-3 py-2 text-base text-ink";

/** Inline "approve a cap exception" form for one engagement. */
export function OverrideForm({ engagementId, tariff, label }: { engagementId: number; tariff: number; label: string }) {
  const id = useId();
  const [sessions, setSessions] = useState("1");
  const [amount, setAmount] = useState(String(tariff));
  const [amountTouched, setAmountTouched] = useState(false);
  const [reason, setReason] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const sessionsNum = Number(sessions);
  const amountNum = Number(amount);
  const valid =
    Number.isInteger(sessionsNum) && sessionsNum >= 0 && sessionsNum <= 100 &&
    Number.isFinite(amountNum) && amountNum >= 0 && amountNum <= 100_000 &&
    (sessionsNum > 0 || amountNum > 0) &&
    reason.trim().length > 0;

  return (
    <details className="group">
      <summary className={`${buttonClass} cursor-pointer list-none`} aria-label={`אישור חריגה: ${label}`}>
        אישור חריגה
      </summary>
      <form
        className="mt-3 space-y-3 rounded-[14px] border border-line p-3"
        onSubmit={(e) => {
          e.preventDefault();
          if (!valid) return;
          setMessage(null);
          startTransition(async () => {
            const result = await addCapOverride({
              engagementId,
              extraSessions: sessionsNum,
              extraAmount: amountNum,
              reason: reason.trim(),
            });
            if (result && !result.ok) setMessage(result.message);
          });
        }}
      >
        {message ? (
          <p role="alert" className="rounded-lg bg-critical-soft px-3 py-2 text-sm font-medium text-critical">
            {message}
          </p>
        ) : null}
        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <label htmlFor={`${id}-s`} className="mb-1 block text-sm font-medium text-ink">
              מפגשים נוספים
            </label>
            <input
              id={`${id}-s`}
              type="number"
              inputMode="numeric"
              min={0}
              max={100}
              step={1}
              value={sessions}
              onChange={(e) => {
                setSessions(e.target.value);
                // Until the amount is edited by hand, keep it at sessions × tariff.
                if (!amountTouched) setAmount(String((Number(e.target.value) || 0) * tariff));
              }}
              className={fieldClass}
            />
          </div>
          <div>
            <label htmlFor={`${id}-a`} className="mb-1 block text-sm font-medium text-ink">
              סכום נוסף (₪)
            </label>
            <input
              id={`${id}-a`}
              type="number"
              inputMode="decimal"
              min={0}
              max={100000}
              step="0.01"
              value={amount}
              onChange={(e) => {
                setAmount(e.target.value);
                setAmountTouched(true);
              }}
              aria-describedby={`${id}-ah`}
              className={fieldClass}
            />
            <p id={`${id}-ah`} className="mt-1 text-xs text-ink-muted">
              לפי תעריף של {formatMoney(tariff)} למפגש. מפגש כפול עולה פי שניים.
            </p>
          </div>
        </div>
        <div>
          <label htmlFor={`${id}-r`} className="mb-1 block text-sm font-medium text-ink">
            סיבה (חובה)
          </label>
          <textarea
            id={`${id}-r`}
            rows={2}
            maxLength={450}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="למשל: אושר מול המפקחת, שני מפגשים נוספים לקראת חנוכה"
            className={fieldClass}
          />
        </div>
        <button type="submit" disabled={pending || !valid} className={buttonClass}>
          {pending ? "שומר…" : "שמירת החריגה"}
        </button>
      </form>
    </details>
  );
}
