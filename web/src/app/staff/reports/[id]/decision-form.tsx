"use client";

import { useState, useTransition } from "react";
import { buttonClass, secondaryButtonClass } from "@/components/ui";
import { decideStaffReport } from "./actions";

const fieldClass =
  "w-full rounded-[10px] border border-field-border bg-surface px-3 py-2.5 text-base text-ink placeholder:text-ink-muted";

export function StaffDecisionForm({
  reportId,
  reasons,
  contentMatches,
}: {
  reportId: number;
  reasons: { id: number; name: string }[];
  /** False when the report changed after the teacher approved it: it can only be returned. */
  contentMatches: boolean;
}) {
  const [mode, setMode] = useState<"approve" | "return">(contentMatches ? "approve" : "return");
  const [confirmed, setConfirmed] = useState(false);
  const [reasonId, setReasonId] = useState<number | null>(null);
  const [comment, setComment] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const otherSelected = reasons.find((r) => r.id === reasonId)?.name === "אחר";
  const canReturn = reasonId !== null && (!otherSelected || comment.trim().length > 0);

  function send(decision: "APPROVE" | "RETURN") {
    setMessage(null);
    startTransition(async () => {
      // On success the action moves to the queue; a returned value is always a failure.
      const result = await decideStaffReport({
        reportId,
        decision,
        reasonId: decision === "RETURN" ? reasonId : null,
        comment: decision === "RETURN" ? comment.trim() : "",
        confirmed: decision === "APPROVE" && confirmed,
      });
      if (result && !result.ok) setMessage(result.message);
    });
  }

  return (
    <section aria-labelledby="staff-decision-title" className="mb-5 rounded-[18px] border border-line bg-surface p-5 shadow-card">
      <h2 id="staff-decision-title" className="mb-3 text-lg font-semibold text-ink">
        {mode === "approve" ? "אישור סופי ונעילה" : "החזרה לספק לתיקון"}
      </h2>

      {message ? (
        <p role="alert" className="mb-3 rounded-lg bg-critical-soft px-3 py-2 text-sm font-medium text-critical">
          {message}
        </p>
      ) : null}

      {mode === "approve" ? (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (confirmed) send("APPROVE");
          }}
        >
          <label className="flex cursor-pointer items-start gap-2 text-ink">
            <input
              type="checkbox"
              checked={confirmed}
              onChange={(e) => setConfirmed(e.target.checked)}
              className="mt-1 size-4 shrink-0 accent-[var(--accent)]"
            />
            <span>בדקתי את הדיווח מול ההתקשרות, ואני מאשרת אותו סופית לתשלום.</span>
          </label>
          <p className="mt-2 text-sm text-ink-muted">
            אחרי הנעילה אי אפשר לשנות את הדיווח, והוא עובר לתור הייצוא של פרוסי.
          </p>

          <div className="mt-4 flex flex-wrap gap-3">
            <button type="submit" disabled={pending || !confirmed} className={buttonClass}>
              {pending ? "שומר…" : "אישור סופי ונעילה"}
            </button>
            <button
              type="button"
              onClick={() => {
                setMode("return");
                setMessage(null);
              }}
              className={secondaryButtonClass}
            >
              החזרה לספק לתיקון
            </button>
          </div>
        </form>
      ) : (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (canReturn) send("RETURN");
          }}
        >
          <fieldset className="mb-4">
            <legend className="mb-2 font-medium text-ink">מה צריך לתקן?</legend>
            {reasons.map((r) => (
              <label key={r.id} className="flex cursor-pointer items-center gap-2 py-1 text-ink">
                <input
                  type="radio"
                  name="staff-reason"
                  value={r.id}
                  checked={reasonId === r.id}
                  onChange={() => setReasonId(r.id)}
                  className="size-4 accent-[var(--accent)]"
                />
                {r.name}
              </label>
            ))}
          </fieldset>

          <label htmlFor="staff-comment" className="mb-1 block font-medium text-ink">
            הערה לספק{otherSelected ? " (חובה)" : " (לא חובה)"}
          </label>
          <textarea
            id="staff-comment"
            rows={3}
            maxLength={450}
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            placeholder="למשל: התעריף בחוזה הוא 250 ₪ למפגש"
            className={fieldClass}
          />
          <p className="mt-1 text-sm text-ink-muted">
            הספק יקבל את הדיווח בחזרה עם הסיבה וההערה. אחרי שיתקן, הדיווח יעבור שוב לחתימת הגננת.
          </p>

          <div className="mt-4 flex flex-wrap gap-3">
            <button type="submit" disabled={pending || !canReturn} className={buttonClass}>
              {pending ? "שומר…" : "החזרה לספק לתיקון"}
            </button>
            {contentMatches ? (
              <button
                type="button"
                onClick={() => {
                  setMode("approve");
                  setMessage(null);
                }}
                className={secondaryButtonClass}
              >
                חזרה לאישור
              </button>
            ) : null}
          </div>
        </form>
      )}
    </section>
  );
}
