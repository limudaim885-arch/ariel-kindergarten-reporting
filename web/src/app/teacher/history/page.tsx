import Link from "next/link";
import { connection } from "next/server";
import {
  PageHead,
  StatusPill,
  secondaryButtonClass,
  stackedBody,
  stackedCell,
  stackedHead,
  stackedRow,
  stackedTable,
} from "@/components/ui";
import { formatDateTime, formatMoney, monthLabel, plural } from "@/lib/format";
import { getTeacherData } from "@/lib/teacher/data";
import { isPending } from "@/lib/teacher/types";

export const metadata = { title: "דיווחים שטופלו - דיווח הגנים" };

export default async function TeacherHistoryPage() {
  await connection();
  const data = await getTeacherData();
  const handled = data.reports.filter((r) => !isPending(r));
  const severalGardens = data.kindergartens.length > 1;

  return (
    <>
      <PageHead
        title="דיווחים שטופלו"
        intro={`${plural(handled.length, "דיווח אחד", "דיווחים")} מ-12 החודשים האחרונים, בגנים שלך.`}
      />

      {handled.length === 0 ? (
        <div className="rounded-[18px] border border-line bg-surface p-6 text-center text-ink-muted shadow-card">
          עדיין אין דיווחים שטופלו.
        </div>
      ) : (
        <div className="rounded-[18px] border border-line bg-surface p-2 shadow-card sm:p-3">
          <table className={stackedTable}>
            <caption className="sr-only">דיווחים שטופלו, החדשים קודם</caption>
            <thead className={stackedHead}>
              <tr className="border-b border-line text-sm text-ink-muted">
                <th scope="col" className="px-3 py-2 font-medium">חודש</th>
                <th scope="col" className="px-3 py-2 font-medium">ספק</th>
                {severalGardens ? <th scope="col" className="px-3 py-2 font-medium">גן</th> : null}
                <th scope="col" className="px-3 py-2 font-medium">מפגשים</th>
                <th scope="col" className="px-3 py-2 font-medium">סכום</th>
                <th scope="col" className="px-3 py-2 font-medium">סטטוס</th>
                <th scope="col" className="px-3 py-2 font-medium">החלטת גננת</th>
                <th scope="col" className="px-3 py-2 font-medium">
                  <span className="sr-only">פעולות</span>
                </th>
              </tr>
            </thead>
            <tbody className={stackedBody}>
              {handled.map((r) => (
                <tr key={r.report_id} className={stackedRow}>
                  <td data-label="חודש" className={stackedCell}>
                    {monthLabel(r.year, r.month)}
                  </td>
                  <td data-label="ספק" className={stackedCell}>
                    {r.supplier.name}
                  </td>
                  {severalGardens ? (
                    <td data-label="גן" className={stackedCell}>
                      {r.kindergarten.name}
                    </td>
                  ) : null}
                  <td data-label="מפגשים" className={`${stackedCell} tabular-nums`}>
                    {r.sessions}
                  </td>
                  <td data-label="סכום" className={`${stackedCell} tabular-nums`}>
                    {formatMoney(r.amount)}
                  </td>
                  <td data-label="סטטוס" className={stackedCell}>
                    <StatusPill status={r.status} label={r.status_name} />
                  </td>
                  <td data-label="החלטת גננת" className={`${stackedCell} text-sm`}>
                    {r.decision
                      ? `${r.decision.decision === "APPROVED" ? "אושר" : "הוחזר"} · ${r.decision.teacher_name} · ${formatDateTime(r.decision.decided_at)}`
                      : r.is_manual || r.kindergarten.is_manual_track
                        ? "טופס ידני"
                        : "-"}
                  </td>
                  <td className="px-3 py-2 max-sm:block max-sm:px-0 max-sm:pt-2">
                    <Link
                      href={`/teacher/reports/${r.report_id}`}
                      className={secondaryButtonClass}
                      aria-label={`פרטים: ${r.supplier.name}, ${monthLabel(r.year, r.month)}`}
                    >
                      פרטים
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
