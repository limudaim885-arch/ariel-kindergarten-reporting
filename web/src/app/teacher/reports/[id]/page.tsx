import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { Callout, PageHead, Panel, StatusPill, secondaryButtonClass } from "@/components/ui";
import { formatDateLong, formatDateTime, formatMoney, monthLabel, plural, weekdayOf } from "@/lib/format";
import { getTeacherData } from "@/lib/teacher/data";
import { isPending } from "@/lib/teacher/types";
import { DecisionForm } from "./decision-form";

export const metadata = { title: "בדיקת דיווח - דיווח הגנים" };

export default async function TeacherReportPage({ params }: PageProps<"/teacher/reports/[id]">) {
  await connection();
  const { id } = await params;
  if (!/^\d{1,9}$/.test(id)) notFound();

  // Only reports of this teacher's kindergartens come back from the database.
  const data = await getTeacherData();
  const report = data.reports.find((r) => r.report_id === Number(id));
  if (!report) notFound();

  const month = monthLabel(report.year, report.month);
  const doubles = report.lines.filter((l) => l.double).length;
  const flagged = report.lines.filter((l) => l.flagged).length;
  const decision = report.decision;

  return (
    <>
      <PageHead
        title={`${report.supplier.name} · ${month}`}
        intro={`${report.kindergarten.name} (${report.kindergarten.code}) · ${report.domain}`}
        action={
          <Link href="/teacher" className={secondaryButtonClass}>
            חזרה לתיבת האישורים
          </Link>
        }
      />

      <Panel>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
          <div>
            <dt className="text-sm text-ink-muted">סטטוס</dt>
            <dd className="mt-1">
              <StatusPill status={report.status} label={report.status_name} />
            </dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">מפגשים</dt>
            <dd className="mt-1 tabular-nums text-ink">
              {report.sessions}
              {doubles ? ` (${plural(doubles, "מפגש כפול אחד", "כפולים")})` : ""}
            </dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">סכום</dt>
            <dd className="mt-1 tabular-nums text-ink">{formatMoney(report.amount)}</dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">נשלח על ידי הספק</dt>
            <dd className="mt-1 text-ink">{report.submitted_at ? formatDateTime(report.submitted_at) : "לא נשלח"}</dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">סוג התקשרות</dt>
            <dd className="mt-1 text-ink">{report.engagement_type}</dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">תעריף למפגש</dt>
            <dd className="mt-1 tabular-nums text-ink">{formatMoney(report.tariff)}</dd>
          </div>
        </dl>
      </Panel>

      <Panel title="ימי הפעילות שדווחו">
        {flagged ? (
          <Callout kind="warning">
            <p>
              {flagged === 1 ? "יום אחד בדיווח הוא שבת או חג." : `${flagged} ימים בדיווח הם שבת או חג.`} כדאי לוודא
              שהפעילות אכן התקיימה בהם.
            </p>
          </Callout>
        ) : null}
        <table className="w-full text-right">
          <caption className="sr-only">ימי הפעילות בדיווח על {month}</caption>
          <thead>
            <tr className="border-b border-line text-sm text-ink-muted">
              <th scope="col" className="py-2 font-medium">תאריך</th>
              <th scope="col" className="py-2 font-medium">סוג מפגש</th>
              <th scope="col" className="py-2 text-left font-medium">סכום</th>
            </tr>
          </thead>
          <tbody>
            {report.lines.map((l) => (
              <tr key={l.date} className="border-b border-line last:border-0">
                <td className="py-2 text-ink">
                  {formatDateLong(l.date)}
                  {l.flagged ? (
                    <span className="text-sm text-critical"> · {weekdayOf(l.date) === 6 ? "שבת" : "חג"}</span>
                  ) : null}
                </td>
                <td className="py-2 text-ink">{l.double ? "כפול" : "רגיל"}</td>
                <td className="py-2 text-left tabular-nums text-ink">{formatMoney(l.amount)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="font-semibold text-ink">
              <td className="pt-3" colSpan={2}>
                סה&quot;כ
              </td>
              <td className="pt-3 text-left tabular-nums">{formatMoney(report.amount)}</td>
            </tr>
          </tfoot>
        </table>
      </Panel>

      {isPending(report) ? (
        <DecisionForm reportId={report.report_id} teacherName={data.teacher.full_name} reasons={data.reasons} />
      ) : decision ? (
        <Callout kind={decision.decision === "APPROVED" ? "success" : "warning"}>
          <p>
            <strong>
              {decision.decision === "APPROVED" ? "אושר" : "הוחזר לספק"} על ידי {decision.teacher_name} ב-
              {formatDateTime(decision.decided_at)}.
            </strong>
            {decision.reason ? ` סיבה: ${decision.reason}.` : ""}
            {decision.comment ? ` ${decision.comment}` : ""}
          </p>
        </Callout>
      ) : report.kindergarten.is_manual_track || report.is_manual ? (
        <Callout kind="info">
          <p>הדיווח הזה במסלול טופס ידני, ולא נחתם כאן.</p>
        </Callout>
      ) : null}
    </>
  );
}
