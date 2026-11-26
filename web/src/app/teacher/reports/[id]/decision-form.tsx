"use client";

import { useState, useTransition } from "react";
import { buttonClass, secondaryButtonClass } from "@/components/ui";
import { decideReport } from "./actions";

const fieldClass =
  "w-full rounded-[10px] border border-field-border bg-surface px-3 py-2.5 text-base text-ink placeholder:text-ink-muted";

export function DecisionForm({
  reportId,
  teacherName,
  reasons,
}: {
  reportId: number;
  teacherName: string;
  reasons: { id: number; name: string }[];
}) {
  const [mode, setMode] = useState<"approve" | "return">("approve");
  const [confirmed, setConfirmed] = useState(false);
  const [signedName, setSignedName] = useState("");
  const [reasonId, setReasonId] = useState<number | null>(null);
  const [comment, setComment] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const otherSelected = reasons.find((r) => r.id === reasonId)?.name === "אחר";
  const canApprove = confirmed && signedName.trim().length > 0;
  const canReturn = reasonId !== null && (!otherSelected || comment.trim().length > 0);

  function send(decision: "APPROVED" | "REJECTED") {
    setMessage(null);
    startTransition(async () => {
      // On success the action moves to the inbox; a returned value is always a failure.
      const result = await decideReport({
        reportId,
        decision,
        reasonId: decision === "REJECTED" ? reasonId : null,
        comment: decision === "REJECTED" ? comment.trim() : "",
        signedName: decision === "APPROVED" ? signedName.trim() : "",
      });
      if (result && !result.ok) setMessage(result.message);
    });
  }

  return (
    <section aria-labelledby="decision-title" className="rounded-[18px] border border-line bg-surface p-5 shadow-card">
      <h2 id="decision-title" className="mb-3 text-lg font-semibold text-ink">
        {mode === "approve" ? "אישור וחתימה" : "החזרה לספק לתיקון"}
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
            if (canApprove) send("APPROVED");
          }}
        >
          <label className="mb-4 flex cursor-pointer items-start gap-2 text-ink">
            <input
              type="checkbox"
              checked={confirmed}
              onChange={(e) => setConfirmed(e.target.checked)}
              className="mt-1 size-4 shrink-0 accent-[var(--accent)]"
            />
            <span>אני מאשרת שהפרטים שלמעלה נכונים ומשקפים את הפעילות שהתקיימה בפועל בגן.</span>
          </label>

          <label htmlFor="signed-name" className="mb-1 block font-medium text-ink">
            חתימה דיגיטלית: יש להקליד את שמך המלא
          </label>
          <input
            id="signed-name"
            type="text"
            autoComplete="name"
            maxLength={100}
            value={signedName}
            onChange={(e) => setSignedName(e.target.value)}
            className={fieldClass}
          />
          <p className="mt-1 text-sm text-ink-muted">
            מחוברת כ{teacherName}. האישור יישמר עם הנייד שלך ועם טביעת התוכן של הדיווח, כדי שאפשר יהיה לוודא
            שהוא לא שונה אחרי החתימה.
          </p>

          <div className="mt-4 flex flex-wrap gap-3">
            <button type="submit" disabled={pending || !canApprove} className={buttonClass}>
              {pending ? "שומר…" : "אישור וחתימה"}
            </button>
            <button
              type="button"
              onClick={() => {
                setMode("return");
                setMessage(null);
              }}
              className={secondaryButtonClass}
            >
              יש בעיה בדיווח
            </button>
          </div>
        </form>
      ) : (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (canReturn) send("REJECTED");
          }}
        >
          <fieldset className="mb-4">
            <legend className="mb-2 font-medium text-ink">מה הבעיה בדיווח?</legend>
            {reasons.map((r) => (
              <label key={r.id} className="flex cursor-pointer items-center gap-2 py-1 text-ink">
                <input
                  type="radio"
                  name="reason"
                  value={r.id}
                  checked={reasonId === r.id}
                  onChange={() => setReasonId(r.id)}
                  className="size-4 accent-[var(--accent)]"
                />
                {r.name}
              </label>
            ))}
          </fieldset>

          <label htmlFor="return-comment" className="mb-1 block font-medium text-ink">
            הערה לספק{otherSelected ? " (חובה)" : " (לא חובה)"}
          </label>
          <textarea
            id="return-comment"
            rows={3}
            maxLength={450}
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            placeholder="למשל: ב-3.11 לא הייתה פעילות בגן"
            className={fieldClass}
          />
          <p className="mt-1 text-sm text-ink-muted">הספק יקבל את הדיווח בחזרה עם הסיבה וההערה, ויוכל לתקן ולשלוח שוב.</p>

          <div className="mt-4 flex flex-wrap gap-3">
            <button type="submit" disabled={pending || !canReturn} className={buttonClass}>
              {pending ? "שומר…" : "החזרה לספק לתיקון"}
            </button>
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
          </div>
        </form>
      )}
    </section>
  );
}
