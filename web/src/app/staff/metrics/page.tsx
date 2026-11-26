import { connection } from "next/server";
import {
  PageHead,
  Panel,
  StatCard,
  stackedBody,
  stackedCell,
  stackedHead,
  stackedRow,
  stackedTable,
} from "@/components/ui";
import { monthLabel } from "@/lib/format";
import { getStaffMetrics } from "@/lib/staff/data";
import type { MetricsMonth } from "@/lib/staff/types";

export const metadata = { title: "מדדים - דיווח הגנים" };

function pct(part: number, whole: number) {
  return whole > 0 ? `${Math.round((part / whole) * 100)}%` : "-";
}

function days(value: number | null) {
  return value === null ? "-" : value.toLocaleString("he-IL", { maximumFractionDigits: 1 });
}

/** A weighted average of a per-month average, by each month's count. */
function weighted(months: MetricsMonth[], avg: (m: MetricsMonth) => number | null, count: (m: MetricsMonth) => number) {
  let sum = 0;
  let n = 0;
  for (const m of months) {
    const a = avg(m);
    if (a !== null && count(m) > 0) {
      sum += a * count(m);
      n += count(m);
    }
  }
  return n ? Math.round((sum / n) * 10) / 10 : null;
}

export default async function StaffMetrics() {
  await connection();
  const { months, suppliers } = await getStaffMetrics();

  // The last three activity months that have reports, for the summary cards.
  const recent = months.slice(-3);
  const sum = (f: (m: MetricsMonth) => number) => recent.reduce((s, m) => s + f(m), 0);
  const bounced = suppliers.filter((s) => s.bounced > 0);

  return (
    <>
      <PageHead
        title="מדדים"
        intro="12 חודשי הפעילות האחרונים. הזמנים בימים קלנדריים, מהשליחה האחרונה של הספק. היעדים לכל מדד עוד לא אושרו, ולכן מוצגים כאן רק המספרים."
      />

      {months.length === 0 ? (
        <div className="rounded-[18px] border border-line bg-surface p-6 text-center text-ink-muted shadow-card">
          עדיין אין דיווחים ב-12 החודשים האחרונים.
        </div>
      ) : (
        <>
          <h2 className="mb-3 text-lg font-semibold text-ink">
            {recent.length === 1
              ? monthLabel(recent[0].year, recent[0].month)
              : `${monthLabel(recent[0].year, recent[0].month)} עד ${monthLabel(recent[recent.length - 1].year, recent[recent.length - 1].month)}`}
          </h2>
          <div className="mb-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
              title="עד אישור הגננת"
              value={days(weighted(recent, (m) => m.avg_days_to_teacher, (m) => m.teacher_approved))}
              sub={`ימים בממוצע · ${pct(sum((m) => m.teacher_within_5_days), sum((m) => m.teacher_approved))} תוך 5 ימים`}
            />
            <StatCard
              title="עד אישור סופי"
              value={days(weighted(recent, (m) => m.avg_days_to_final, (m) => m.final))}
              sub="ימים בממוצע, משליחת הספק"
            />
            <StatCard
              title="הוחזרו או נדחו"
              value={pct(sum((m) => m.bounced), sum((m) => m.reports))}
              sub={`${sum((m) => m.bounced)} מתוך ${sum((m) => m.reports)} דיווחים`}
            />
            <StatCard
              title="אישור דיגיטלי"
              value={pct(sum((m) => m.digital), sum((m) => m.approved))}
              sub="מהדיווחים שהגננת אישרה"
            />
          </div>

          <Panel title="לפי חודש פעילות">
            <table className={stackedTable}>
              <caption className="sr-only">מדדים לפי חודש פעילות</caption>
              <thead className={stackedHead}>
                <tr className="border-b border-line text-sm text-ink-muted">
                  <th scope="col" className="px-3 py-2 font-medium">חודש</th>
                  <th scope="col" className="px-3 py-2 font-medium">דיווחים</th>
                  <th scope="col" className="px-3 py-2 font-medium">עד אישור הגננת (ממוצע)</th>
                  <th scope="col" className="px-3 py-2 font-medium">הגננת אישרה תוך 5 ימים</th>
                  <th scope="col" className="px-3 py-2 font-medium">עד אישור סופי (ממוצע)</th>
                  <th scope="col" className="px-3 py-2 font-medium">הארוך ביותר</th>
                  <th scope="col" className="px-3 py-2 font-medium">הוחזרו או נדחו</th>
                  <th scope="col" className="px-3 py-2 font-medium">דיגיטלי</th>
                </tr>
              </thead>
              <tbody className={stackedBody}>
                {[...months].reverse().map((m) => (
                  <tr key={`${m.year}-${m.month}`} className={stackedRow}>
                    <td data-label="חודש" className={stackedCell}>
                      {monthLabel(m.year, m.month)}
                    </td>
                    <td data-label="דיווחים" className={`${stackedCell} tabular-nums`}>
                      {m.reports}
                    </td>
                    <td data-label="עד אישור הגננת (ממוצע)" className={`${stackedCell} tabular-nums`}>
                      {days(m.avg_days_to_teacher)}
                    </td>
                    <td data-label="הגננת אישרה תוך 5 ימים" className={`${stackedCell} tabular-nums`}>
                      {pct(m.teacher_within_5_days, m.teacher_approved)}
                    </td>
                    <td data-label="עד אישור סופי (ממוצע)" className={`${stackedCell} tabular-nums`}>
                      {days(m.avg_days_to_final)}
                    </td>
                    <td data-label="הארוך ביותר" className={`${stackedCell} tabular-nums`}>
                      {days(m.max_days_to_final)}
                    </td>
                    <td data-label="הוחזרו או נדחו" className={`${stackedCell} tabular-nums`}>
                      {pct(m.bounced, m.reports)}
                    </td>
                    <td data-label="דיגיטלי" className={`${stackedCell} tabular-nums`}>
                      {pct(m.digital, m.approved)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Panel>

          <Panel title="ספקים שדיווחים שלהם הוחזרו או נדחו">
            {bounced.length === 0 ? (
              <p className="text-ink-muted">אף דיווח לא הוחזר או נדחה ב-12 החודשים האחרונים.</p>
            ) : (
              <table className={stackedTable}>
                <caption className="sr-only">אחוז הדיווחים שהוחזרו או נדחו, לפי ספק</caption>
                <thead className={stackedHead}>
                  <tr className="border-b border-line text-sm text-ink-muted">
                    <th scope="col" className="px-3 py-2 font-medium">ספק</th>
                    <th scope="col" className="px-3 py-2 font-medium">מספר ספק</th>
                    <th scope="col" className="px-3 py-2 font-medium">דיווחים</th>
                    <th scope="col" className="px-3 py-2 font-medium">הוחזרו או נדחו</th>
                    <th scope="col" className="px-3 py-2 font-medium">אחוז</th>
                  </tr>
                </thead>
                <tbody className={stackedBody}>
                  {bounced.map((s) => (
                    <tr key={s.supplier_id} className={stackedRow}>
                      <td data-label="ספק" className={stackedCell}>
                        {s.name}
                      </td>
                      <td data-label="מספר ספק" className={`${stackedCell} tabular-nums`}>
                        {s.number}
                      </td>
                      <td data-label="דיווחים" className={`${stackedCell} tabular-nums`}>
                        {s.reports}
                      </td>
                      <td data-label="הוחזרו או נדחו" className={`${stackedCell} tabular-nums`}>
                        {s.bounced}
                      </td>
                      <td data-label="אחוז" className={`${stackedCell} tabular-nums`}>
                        {pct(s.bounced, s.reports)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            <p className="mt-3 text-sm text-ink-muted">
              דיווח נספר פעם אחת גם אם הוחזר כמה פעמים, וגם אם כבר תוקן מאז.
            </p>
          </Panel>
        </>
      )}
    </>
  );
}
