import Link from "next/link";
import { connection } from "next/server";
import {
  Callout,
  PageHead,
  buttonClass,
  stackedBody,
  stackedCell,
  stackedHead,
  stackedRow,
  stackedTable,
} from "@/components/ui";
import { formatDateTime, formatMoney, monthLabel } from "@/lib/format";
import { getStaffReports } from "@/lib/staff/data";

export const metadata = { title: "תור אישורים - דיווח הגנים" };

const DONE: Record<string, string> = {
  locked: "הדיווח אושר סופית וננעל, ועבר לתור של פרוסי.",
  returned: "הדיווח הוחזר לספק לתיקון, יחד עם הסיבה וההערה.",
};

export default async function StaffQueue({ searchParams }: PageProps<"/staff/queue">) {
  await connection();
  const { staff, reports } = await getStaffReports();
  const done = (await searchParams).done;
  const doneText = typeof done === "string" ? DONE[done] : undefined;

  // Oldest teacher approval first: it has waited longest.
  const queue = reports
    .filter((r) => r.status === "TEACHER_APPROVED")
    .sort((a, b) => (a.teacher_decision?.decided_at ?? "").localeCompare(b.teacher_decision?.decided_at ?? ""));

  return (
    <>
      <PageHead
        title="תור אישורים"
        intro="דיווחים שהגננת אישרה, וממתינים לבדיקה ולאישור סופי. הוותיקים ביותר ראשונים."
      />

      {doneText ? (
        <Callout kind="success" role="status">
          <p>
            <strong>{doneText}</strong>
          </p>
        </Callout>
      ) : null}

      {!staff.can_act ? (
        <Callout kind="info">
          <p>ההרשאה שלך היא צפייה בלבד. אפשר לראות את הדיווחים, אבל לא לאשר או להחזיר אותם.</p>
        </Callout>
      ) : null}

      {queue.length === 0 ? (
        <div className="rounded-[18px] border border-line bg-surface p-6 text-center text-ink-muted shadow-card">
          אין כרגע דיווחים שממתינים לאישור סופי.
        </div>
      ) : (
        <div className="rounded-[18px] border border-line bg-surface p-2 shadow-card sm:p-3">
          <table className={stackedTable}>
            <caption className="sr-only">דיווחים שממתינים לאישור סופי, הוותיקים קודם</caption>
            <thead className={stackedHead}>
              <tr className="border-b border-line text-sm text-ink-muted">
                <th scope="col" className="px-3 py-2 font-medium">חודש</th>
                <th scope="col" className="px-3 py-2 font-medium">ספק</th>
                <th scope="col" className="px-3 py-2 font-medium">גן</th>
                <th scope="col" className="px-3 py-2 font-medium">מפגשים</th>
                <th scope="col" className="px-3 py-2 font-medium">סכום</th>
                <th scope="col" className="px-3 py-2 font-medium">אישור הגננת</th>
                <th scope="col" className="px-3 py-2 font-medium">
                  <span className="sr-only">פעולות</span>
                </th>
              </tr>
            </thead>
            <tbody className={stackedBody}>
              {queue.map((r) => (
                <tr key={r.report_id} className={stackedRow}>
                  <td data-label="חודש" className={stackedCell}>
                    {monthLabel(r.year, r.month)}
                  </td>
                  <td data-label="ספק" className={stackedCell}>
                    {r.supplier.name}
                  </td>
                  <td data-label="גן" className={stackedCell}>
                    <span>
                      {r.kindergarten.name}
                      {r.kindergarten.is_mine ? <span className="text-sm text-ink-muted"> (שלך)</span> : null}
                    </span>
                  </td>
                  <td data-label="מפגשים" className={`${stackedCell} tabular-nums`}>
                    {r.sessions}
                  </td>
                  <td data-label="סכום" className={`${stackedCell} tabular-nums`}>
                    {formatMoney(r.amount)}
                  </td>
                  <td data-label="אישור הגננת" className={`${stackedCell} text-sm`}>
                    {r.teacher_decision
                      ? `${r.teacher_decision.teacher_name} · ${formatDateTime(r.teacher_decision.decided_at)}`
                      : "-"}
                  </td>
                  <td className="px-3 py-2 max-sm:block max-sm:px-0 max-sm:pt-2">
                    <Link
                      href={`/staff/reports/${r.report_id}`}
                      className={buttonClass}
                      aria-label={`בדיקה: ${r.supplier.name}, ${r.kindergarten.name}, ${monthLabel(r.year, r.month)}`}
                    >
                      בדיקה
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
