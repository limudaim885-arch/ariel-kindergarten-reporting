"use client";

import { useMemo, useState, useTransition } from "react";
import { Callout, CapBar, Panel, buttonClass } from "@/components/ui";
import { addMonths, formatDateLong, formatMoney, monthLabelOf, plural, weekdayOf, ymKey, ymOf } from "@/lib/format";
import { BLOCK_REASON_TEXT, type Engagement, type Report, type SubmitItem } from "@/lib/supplier/types";
import { submitReport } from "./actions";
import { MonthCalendar, type DayInfo } from "./calendar";

/** engagement id -> date -> is double session */
type Selection = Record<number, Record<string, boolean>>;

// ref.session_types: a double session pays twice and counts once toward the session cap.
// The database recalculates everything; this is only for the on-screen estimate.
const DOUBLE_MULTIPLIER = 2;

const linkButton = "text-sm font-medium text-accent underline underline-offset-2";

function rangeOf(e: Engagement, today: string, minDate: string) {
  const from = e.school_year.start > minDate ? e.school_year.start : minDate;
  const to = e.school_year.end < today ? e.school_year.end : today;
  return { from, to };
}

/** Early in the month suppliers usually report the month that just ended. */
function defaultMonth(e: Engagement, today: string, minDate: string) {
  const { from, to } = rangeOf(e, today, minDate);
  const last = ymOf(to);
  const prev = addMonths(last, -1);
  if (to === today && Number(today.slice(8)) <= 7 && prev >= ymOf(from)) return prev;
  return last;
}

function restDayOf(date: string, holidays: Map<string, string>) {
  const holiday = holidays.get(date);
  if (holiday) return `חג: ${holiday}`;
  return weekdayOf(date) === 6 ? "שבת" : null;
}

export function ReportForm({
  engagements,
  reports,
  today,
  minDate,
  holidays,
  initialEngagementId,
  fixReportId,
}: {
  engagements: Engagement[];
  reports: Report[];
  today: string;
  minDate: string;
  holidays: { date: string; name: string }[];
  initialEngagementId: number | null;
  fixReportId: number | null;
}) {
  const engById = useMemo(() => new Map(engagements.map((e) => [e.engagement_id, e])), [engagements]);
  const reportByMonth = useMemo(
    () => new Map(reports.map((r) => [`${r.engagement_id}:${ymKey(r.year, r.month)}`, r])),
    [reports],
  );
  const holidayByDate = useMemo(() => new Map(holidays.map((h) => [h.date, h.name])), [holidays]);

  const fixReport = fixReportId
    ? reports.find((r) => r.report_id === fixReportId && r.editable && engById.has(r.engagement_id))
    : undefined;

  const [engagementId, setEngagementId] = useState<number | null>(() => {
    if (fixReport) return fixReport.engagement_id;
    if (initialEngagementId && engById.get(initialEngagementId)?.block_reason === null) return initialEngagementId;
    const open = engagements.filter((e) => e.block_reason === null);
    return open.length === 1 ? open[0].engagement_id : null;
  });
  const [selection, setSelection] = useState<Selection>(() =>
    fixReport
      ? { [fixReport.engagement_id]: Object.fromEntries(fixReport.lines.map((l) => [l.date, l.double])) }
      : {},
  );
  const [viewYm, setViewYm] = useState<string>(() => {
    if (fixReport) return ymKey(fixReport.year, fixReport.month);
    const e = engagementId ? engById.get(engagementId) : undefined;
    return e ? defaultMonth(e, today, minDate) : ymOf(today);
  });
  const [errors, setErrors] = useState<Record<number, string[]>>({});
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const engagement = engagementId ? (engById.get(engagementId) ?? null) : null;
  const range = engagement ? rangeOf(engagement, today, minDate) : null;
  const days = engagementId ? (selection[engagementId] ?? {}) : {};
  const selectedDates = Object.keys(days).sort();
  const viewReport = engagementId ? reportByMonth.get(`${engagementId}:${viewYm}`) : undefined;

  function chooseEngagement(id: number | null) {
    setEngagementId(id);
    const e = id ? engById.get(id) : undefined;
    if (e) setViewYm(defaultMonth(e, today, minDate));
  }

  function update(id: number, change: (dates: Record<string, boolean>) => void) {
    setSelection((prev) => {
      const next = { ...(prev[id] ?? {}) };
      change(next);
      return { ...prev, [id]: next };
    });
    setErrors((prev) => {
      if (!(id in prev)) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
    setMessage(null);
  }

  function toggleDay(date: string) {
    if (!engagementId) return;
    update(engagementId, (d) => {
      if (date in d) delete d[date];
      else d[date] = false;
    });
  }

  function toggleDouble(date: string) {
    if (!engagementId) return;
    update(engagementId, (d) => {
      if (date in d) d[date] = !d[date];
    });
  }

  function loadReport(r: Report) {
    update(r.engagement_id, (d) => {
      for (const line of r.lines) d[line.date] = line.double;
    });
  }

  function clearEngagement(id: number) {
    update(id, (d) => {
      for (const key of Object.keys(d)) delete d[key];
    });
  }

  function dayInfo(date: string): DayInfo {
    const rep = reportByMonth.get(`${engagementId}:${ymOf(date)}`);
    const locked = !!rep && !rep.editable;
    const inRange = !!range && date >= range.from && date <= range.to;
    return {
      selectable: inRange && !locked && engagement?.block_reason === null,
      sent: locked && rep.lines.some((l) => l.date === date),
      inReturned: !!rep && rep.editable && rep.lines.some((l) => l.date === date),
      selected: date in days,
      double: !!days[date],
      restDay: restDayOf(date, holidayByDate),
    };
  }

  // What is about to be sent, per garden, with an estimate against the cap.
  const summary = useMemo(
    () =>
      Object.entries(selection).flatMap(([idText, dates]) => {
        const id = Number(idText);
        const e = engById.get(id);
        const list = Object.keys(dates).sort();
        if (!e || list.length === 0) return [];
        const sessions = list.length;
        const amount = list.reduce((sum, date) => sum + e.tariff * (dates[date] ? DOUBLE_MULTIPLIER : 1), 0);
        const months = [...new Set(list.map(ymOf))].sort();
        const replaced = months
          .map((m) => reportByMonth.get(`${id}:${m}`))
          .filter((r): r is Report => !!r && r.editable);
        // A rejected report is not counted in the usage already, so only returned ones are taken off.
        const counted = replaced.filter((r) => r.status !== "TEACHER_REJECTED");
        const leftSessions = e.session_cap - (e.sessions_used - counted.reduce((s, r) => s + r.sessions, 0));
        const leftAmount = e.amount_cap - (e.amount_used - counted.reduce((s, r) => s + r.amount, 0));
        const over = sessions > leftSessions || amount > leftAmount + 0.001;
        return [{ e, list, dates, sessions, amount, months, replaced, leftSessions, leftAmount, over }];
      }),
    [selection, engById, reportByMonth],
  );
  const total = summary.reduce((sum, s) => sum + s.amount, 0);
  const anyOver = summary.some((s) => s.over);

  function submit() {
    setMessage(null);
    setErrors({});
    const items: SubmitItem[] = summary.map((s) => ({
      engagementId: s.e.engagement_id,
      lines: s.list.map((date) => ({ date, double: s.dates[date] })),
    }));
    startTransition(async () => {
      // On success the action moves to "My reports"; a returned value is always a failure.
      const result = await submitReport(items);
      if (!result) return;
      if ("errors" in result) {
        const byId: Record<number, string[]> = {};
        for (const err of result.errors) (byId[err.engagementId] ??= []).push(err.message);
        setErrors(byId);
        setMessage("שום דיווח לא נשלח. יש לתקן את מה שמסומן ברשימת השליחה ולשלוח שוב.");
      } else {
        setMessage(result.message);
      }
    });
  }

  return (
    <div className="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_22rem]">
      <Panel className="mb-0">
        {fixReport ? (
          <Callout kind="warning">
            <p>
              <strong>
                תיקון הדיווח על {monthLabelOf(ymKey(fixReport.year, fixReport.month))} ב{fixReport.kindergarten.name}.
              </strong>{" "}
              הימים מהדיווח המקורי כבר מסומנים. אפשר להוסיף ימים, להסיר ימים או לשנות מפגש כפול, ואז לשלוח מחדש.
            </p>
            {fixReport.note && (fixReport.note.reason || fixReport.note.comment) ? (
              <p className="mt-1">
                ההערה שהתקבלה: {[fixReport.note.reason, fixReport.note.comment].filter(Boolean).join(". ")}
              </p>
            ) : null}
          </Callout>
        ) : null}

        <label htmlFor="engagement" className="mb-1 block font-medium text-ink">
          גן
        </label>
        <select
          id="engagement"
          value={engagementId ?? ""}
          onChange={(ev) => chooseEngagement(ev.target.value ? Number(ev.target.value) : null)}
          className="w-full rounded-[10px] border border-field-border bg-surface px-3 py-2.5 text-base text-ink"
        >
          <option value="">בחירת גן…</option>
          {engagements.map((e) => (
            <option key={e.engagement_id} value={e.engagement_id} disabled={e.block_reason !== null}>
              {e.kindergarten.name} ({e.kindergarten.code}) · {e.domain}
              {e.block_reason === "MANUAL_TRACK"
                ? " · מסלול ידני"
                : e.block_reason === "NEEDS_SUPERVISOR_APPROVAL"
                  ? " · ממתין לאישור מפקחת"
                  : ""}
            </option>
          ))}
        </select>

        {engagements.length === 0 ? (
          <p className="mt-3 text-ink-muted">עדיין לא שויכו אליך גנים. יש לפנות לרפרנטית.</p>
        ) : null}

        {engagement && range ? (
          <>
            <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-4">
              <div>
                <dt className="text-ink-muted">תחום</dt>
                <dd className="text-ink">{engagement.domain}</dd>
              </div>
              <div>
                <dt className="text-ink-muted">סוג התקשרות</dt>
                <dd className="text-ink">{engagement.engagement_type}</dd>
              </div>
              <div>
                <dt className="text-ink-muted">תעריף למפגש</dt>
                <dd className="tabular-nums text-ink">{formatMoney(engagement.tariff)}</dd>
              </div>
              <div>
                <dt className="text-ink-muted">גננת</dt>
                <dd className="text-ink">{engagement.teachers.join(", ") || "אין גננת משובצת"}</dd>
              </div>
            </dl>

            <div className="mt-4">
              <CapBar
                label="מפגשים בשנת הלימודים"
                used={engagement.sessions_used}
                cap={engagement.session_cap}
                text={`${engagement.sessions_used} מתוך ${engagement.session_cap}`}
              />
              <CapBar
                label="סכום בשנת הלימודים"
                used={engagement.amount_used}
                cap={engagement.amount_cap}
                text={`${formatMoney(engagement.amount_used)} מתוך ${formatMoney(engagement.amount_cap)}`}
              />
              <p className="text-sm text-ink-muted">מפגש כפול מחושב בתעריף כפול, ונספר כמפגש אחד בתקרת המפגשים.</p>
            </div>

            {engagement.block_reason ? (
              <div className="mt-4">
                <Callout kind="info">
                  <p>{BLOCK_REASON_TEXT[engagement.block_reason]}</p>
                </Callout>
              </div>
            ) : (
              <div className="mt-5">
                {engagement.is_blocked ? (
                  <Callout kind="critical">
                    <p>
                      <strong>הגעת לתקרת ההתקשרות בגן הזה.</strong> אפשר רק לתקן דיווח שהוחזר. לדיווח על מפגשים נוספים
                      יש לפנות לרפרנטית, והיא תאשר חריגה במערכת.
                    </p>
                  </Callout>
                ) : null}

                {viewReport && !viewReport.editable ? (
                  <Callout kind="info" role="status">
                    <p>
                      הדיווח על {monthLabelOf(viewYm)} כבר נשלח ({viewReport.status_name}). הימים שדווחו מסומנים ב-✓,
                      ואי אפשר לשנות אותם מכאן. לתיקון יש לפנות לרפרנטית.
                    </p>
                  </Callout>
                ) : null}

                {viewReport && viewReport.editable && viewReport.report_id !== fixReport?.report_id ? (
                  <Callout kind="warning" role="status">
                    <p>
                      <strong>הדיווח על {monthLabelOf(viewYm)} הוחזר לתיקון.</strong> הימים שתסמן לחודש הזה יחליפו
                      אותו בשליחה.
                    </p>
                    <button type="button" onClick={() => loadReport(viewReport)} className={`${linkButton} mt-1`}>
                      סימון הימים מהדיווח שהוחזר
                    </button>
                  </Callout>
                ) : null}

                <MonthCalendar
                  ym={viewYm}
                  minYm={ymOf(range.from)}
                  maxYm={ymOf(range.to)}
                  today={today}
                  dayInfo={dayInfo}
                  onToggle={toggleDay}
                  onMonthChange={setViewYm}
                />

                <h3 className="mb-2 mt-5 font-semibold text-ink">
                  הימים שסומנו ב{engagement.kindergarten.name}
                  {selectedDates.length ? ` (${selectedDates.length})` : ""}
                </h3>
                {selectedDates.length === 0 ? (
                  <p className="text-ink-muted">עדיין לא סומנו ימים. יש ללחוץ על הימים בלוח.</p>
                ) : (
                  <>
                    <ul className="divide-y divide-line">
                      {selectedDates.map((date) => {
                        const rest = restDayOf(date, holidayByDate);
                        return (
                          <li key={date} className="flex flex-wrap items-center justify-between gap-2 py-2">
                            <span className="text-ink">
                              {formatDateLong(date)}
                              {rest ? <span className="text-sm text-critical"> · {rest}</span> : null}
                            </span>
                            <span className="flex items-center gap-4">
                              <label className="flex cursor-pointer items-center gap-1.5 text-sm text-ink">
                                <input
                                  type="checkbox"
                                  checked={days[date]}
                                  onChange={() => toggleDouble(date)}
                                  className="size-4 accent-[var(--accent)]"
                                />
                                מפגש כפול
                              </label>
                              <span className="w-20 text-left text-sm tabular-nums text-ink">
                                {formatMoney(engagement.tariff * (days[date] ? DOUBLE_MULTIPLIER : 1))}
                              </span>
                              <button
                                type="button"
                                onClick={() => toggleDay(date)}
                                className={linkButton}
                                aria-label={`הסרת ${formatDateLong(date)}`}
                              >
                                הסרה
                              </button>
                            </span>
                          </li>
                        );
                      })}
                    </ul>
                    {selectedDates.some((d) => restDayOf(d, holidayByDate)) ? (
                      <p className="mt-2 text-sm text-ink-muted">ביקור בשבת או בחג יסומן לבדיקה של הרפרנטית.</p>
                    ) : null}
                  </>
                )}
              </div>
            )}
          </>
        ) : null}
      </Panel>

      <aside aria-label="רשימת השליחה" className="lg:sticky lg:top-4">
        <Panel title="רשימת השליחה" className="mb-0">
          {summary.length === 0 ? (
            <p className="mb-4 text-ink-muted">
              עדיין לא סומנו ימים לשליחה. אפשר לסמן ימים בכמה גנים ולשלוח את כולם יחד.
            </p>
          ) : (
            <ul className="mb-4 space-y-3">
              {summary.map((s) => {
                const id = s.e.engagement_id;
                const problems = errors[id] ?? [];
                return (
                  <li
                    key={id}
                    className={`rounded-xl border p-3 ${problems.length || s.over ? "border-critical" : "border-line"}`}
                  >
                    <div className="flex items-baseline justify-between gap-2">
                      <strong className="text-ink">{s.e.kindergarten.name}</strong>
                      <span className="tabular-nums text-ink">{formatMoney(s.amount)}</span>
                    </div>
                    <p className="text-sm text-ink-muted">
                      {s.e.domain} · {plural(s.sessions, "מפגש אחד", "מפגשים")} ·{" "}
                      {s.months.map(monthLabelOf).join(", ")}
                    </p>
                    {s.replaced.length ? (
                      <p className="mt-1 text-sm text-warning">
                        יחליף את הדיווח שהוחזר על{" "}
                        {s.replaced.map((r) => monthLabelOf(ymKey(r.year, r.month))).join(", ")}
                      </p>
                    ) : null}
                    {s.over ? (
                      <p className="mt-1 text-sm text-critical">
                        עובר את תקרת ההתקשרות: נותרו {Math.max(s.leftSessions, 0)} מפגשים ו-
                        {formatMoney(Math.max(s.leftAmount, 0))}. לאישור חריגה יש לפנות לרפרנטית.
                      </p>
                    ) : null}
                    {problems.map((p) => (
                      <p key={p} className="mt-1 text-sm text-critical">
                        {p}
                      </p>
                    ))}
                    <div className="mt-2 flex gap-4">
                      {id !== engagementId ? (
                        <button type="button" onClick={() => chooseEngagement(id)} className={linkButton}>
                          עריכה
                        </button>
                      ) : null}
                      <button type="button" onClick={() => clearEngagement(id)} className={linkButton}>
                        הסרה מהרשימה
                      </button>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}

          <p className="mb-3 flex justify-between border-t border-line pt-3 text-ink">
            <span>סה&quot;כ לשליחה</span>
            <strong className="tabular-nums">{formatMoney(total)}</strong>
          </p>

          {message ? (
            <p role="alert" className="mb-3 rounded-lg bg-critical-soft px-3 py-2 text-sm font-medium text-critical">
              {message}
            </p>
          ) : null}

          <button
            type="button"
            onClick={submit}
            disabled={pending || summary.length === 0 || anyOver}
            className={`${buttonClass} w-full`}
          >
            {pending ? "שולח…" : "שליחה לחתימת הגננות"}
          </button>
          <p className="mt-2 text-sm text-ink-muted">אחרי השליחה הדיווח של כל גן עובר לחתימת הגננת שלו.</p>
        </Panel>
      </aside>
    </div>
  );
}
