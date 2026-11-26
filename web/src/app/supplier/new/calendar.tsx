"use client";

import { HE_WEEKDAYS, addMonths, daysInMonth, formatDateLong, monthLabelOf, weekdayOf } from "@/lib/format";

export type DayInfo = {
  /** Can the supplier mark this day? */
  selectable: boolean;
  /** Already in a report that was sent and not returned. */
  sent: boolean;
  /** Was in a report that came back for a fix. */
  inReturned: boolean;
  selected: boolean;
  double: boolean;
  /** Saturday or holiday name. */
  restDay: string | null;
};

const SHORT_DAYS = ["א", "ב", "ג", "ד", "ה", "ו", "ש"];

/** One month, Sunday first. In RTL the first column is on the right, as in a Hebrew calendar. */
export function MonthCalendar({
  ym,
  minYm,
  maxYm,
  today,
  dayInfo,
  onToggle,
  onMonthChange,
}: {
  ym: string;
  minYm: string;
  maxYm: string;
  today: string;
  dayInfo: (date: string) => DayInfo;
  onToggle: (date: string) => void;
  onMonthChange: (ym: string) => void;
}) {
  const days = daysInMonth(ym);
  const firstWeekday = weekdayOf(`${ym}-01`);
  const cells: (string | null)[] = [
    ...Array.from({ length: firstWeekday }, () => null),
    ...Array.from({ length: days }, (_, i) => `${ym}-${String(i + 1).padStart(2, "0")}`),
  ];
  while (cells.length % 7) cells.push(null);
  const weeks = Array.from({ length: cells.length / 7 }, (_, w) => cells.slice(w * 7, w * 7 + 7));

  const prev = addMonths(ym, -1);
  const next = addMonths(ym, 1);
  const navClass =
    "rounded-[10px] border border-line-strong px-3 py-1.5 text-sm font-medium text-ink hover:bg-surface-2 disabled:invisible";

  return (
    <div>
      <div className="mb-2 flex items-center justify-between gap-2">
        <button
          type="button"
          className={navClass}
          onClick={() => onMonthChange(prev)}
          disabled={prev < minYm}
          aria-label={`לחודש הקודם, ${monthLabelOf(prev)}`}
        >
          → <span className="max-sm:hidden">{monthLabelOf(prev)}</span>
        </button>
        <h3 className="whitespace-nowrap text-lg font-semibold text-ink" aria-live="polite">
          {monthLabelOf(ym)}
        </h3>
        <button
          type="button"
          className={navClass}
          onClick={() => onMonthChange(next)}
          disabled={next > maxYm}
          aria-label={`לחודש הבא, ${monthLabelOf(next)}`}
        >
          <span className="max-sm:hidden">{monthLabelOf(next)}</span> ←
        </button>
      </div>

      <table className="w-full table-fixed border-separate border-spacing-1">
        <caption className="sr-only">
          ימי הפעילות ב{monthLabelOf(ym)}. לחיצה על יום מסמנת אותו, ולחיצה נוספת מבטלת את הסימון.
        </caption>
        <thead>
          <tr>
            {SHORT_DAYS.map((d, i) => (
              <th key={d} scope="col" abbr={HE_WEEKDAYS[i]} className="pb-1 text-sm font-medium text-ink-muted">
                {d}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {weeks.map((week, w) => (
            <tr key={w}>
              {week.map((date, i) =>
                date ? (
                  <td key={date} className="p-0">
                    <Day date={date} today={today} info={dayInfo(date)} onToggle={onToggle} />
                  </td>
                ) : (
                  <td key={`e${w}-${i}`} />
                ),
              )}
            </tr>
          ))}
        </tbody>
      </table>

      <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-sm text-ink-muted" aria-label="מקרא">
        <li className="flex items-center gap-1.5">
          <span aria-hidden="true" className="inline-block size-3.5 rounded bg-accent" /> נבחר לשליחה
        </li>
        <li className="flex items-center gap-1.5">
          <span aria-hidden="true" className="inline-block size-3.5 rounded bg-success-soft ring-1 ring-success" /> כבר
          נשלח
        </li>
        <li className="flex items-center gap-1.5">
          <span aria-hidden="true" className="inline-block size-3.5 rounded border-2 border-dashed border-critical" /> היה
          בדיווח שהוחזר
        </li>
        <li className="flex items-center gap-1.5">
          <span aria-hidden="true" className="text-critical">●</span> שבת או חג
        </li>
      </ul>
    </div>
  );
}

function Day({
  date,
  today,
  info,
  onToggle,
}: {
  date: string;
  today: string;
  info: DayInfo;
  onToggle: (date: string) => void;
}) {
  const dayNumber = Number(date.slice(8));
  const parts = [formatDateLong(date)];
  if (info.restDay) parts.push(info.restDay);
  if (info.sent) parts.push("כבר נשלח");
  else if (info.selected) parts.push(info.double ? "נבחר, מפגש כפול" : "נבחר");
  if (info.inReturned && !info.selected) parts.push("היה בדיווח שהוחזר לתיקון");

  let tone = "text-ink hover:bg-surface-2";
  if (info.selected) tone = "bg-accent text-on-fill hover:bg-accent-strong";
  else if (info.sent) tone = "bg-success-soft text-success ring-1 ring-success";
  else if (!info.selectable) tone = "text-ink-muted opacity-40";
  const returned = info.inReturned && !info.selected ? "border-2 border-dashed border-critical" : "border-2 border-transparent";

  return (
    <button
      type="button"
      onClick={() => onToggle(date)}
      disabled={!info.selectable}
      aria-pressed={info.selectable ? info.selected : undefined}
      aria-label={parts.join(", ")}
      aria-current={date === today ? "date" : undefined}
      className={`relative flex h-11 w-full flex-col items-center justify-center rounded-lg text-base tabular-nums disabled:cursor-not-allowed ${tone} ${returned} ${
        date === today ? "font-bold underline underline-offset-4" : ""
      }`}
    >
      <span aria-hidden="true">{dayNumber}</span>
      {info.selected && info.double ? (
        <span aria-hidden="true" dir="ltr" className="text-[0.65rem] leading-none">
          ×2
        </span>
      ) : null}
      {info.sent ? (
        <span aria-hidden="true" className="text-[0.65rem] leading-none">
          ✓
        </span>
      ) : null}
      {info.restDay ? (
        <span aria-hidden="true" className={`absolute left-1 top-0.5 text-[0.6rem] ${info.selected ? "" : "text-critical"}`}>
          ●
        </span>
      ) : null}
    </button>
  );
}
