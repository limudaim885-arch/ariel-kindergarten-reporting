import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { Callout, PageHead, Panel, StatusPill, buttonClass, secondaryButtonClass } from "@/components/ui";
import { formatDateLong, formatDateTime, formatMoney, monthLabel, plural, weekdayOf } from "@/lib/format";
import { getSupplierData } from "@/lib/supplier/data";

export const metadata = { title: "פרטי דיווח - דיווח הגנים" };

const BY: Record<string, string> = {
  TEACHER: "הגננת",
  STAFF: "הרפרנטית",
  SUPPLIER_CONTACT: "הספק",
  SYSTEM: "המערכת",
};

export default async function SupplierReportPage({ params }: PageProps<"/supplier/reports/[id]">) {
  await connection();
  const { id } = await params;
  if (!/^\d{1,9}$/.test(id)) notFound();

  // Only this supplier's reports come back from the database, so another
  // supplier's report id simply is not found.
  const { reports } = await getSupplierData();
  const report = reports.find((r) => r.report_id === Number(id));
  if (!report) notFound();

  const month = monthLabel(report.year, report.month);
  const doubles = report.lines.filter((l) => l.double).length;

  return (
    <>
      <PageHead
        title={`${report.kindergarten.name} · ${month}`}
        intro={`${report.domain} · סמל גן ${report.kindergarten.code}`}
        action={
          <Link href="/supplier/reports" className={secondaryButtonClass}>
            חזרה לדיווחים שלי
          </Link>
        }
      />

      {report.editable && report.note ? (
        <Callout kind="critical">
          <p>
            <strong>הדיווח הוחזר לתיקון על ידי {BY[report.note.by] ?? "הצוות"}.</strong>
            {report.note.reason ? ` סיבה: ${report.note.reason}.` : ""}
            {report.note.comment ? ` הערה: ${report.note.comment}` : ""}
          </p>
        </Callout>
      ) : null}

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
            <dt className="text-sm text-ink-muted">נשלח</dt>
            <dd className="mt-1 text-ink">{report.submitted_at ? formatDateTime(report.submitted_at) : "לא נשלח"}</dd>
          </div>
        </dl>
        {report.is_manual ? (
          <p className="mt-3 text-sm text-ink-muted">הדיווח הוזן על ידי הרפרנטית מטופס נייר.</p>
        ) : null}
      </Panel>

      <Panel title="ימי הפעילות">
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
                    <span className="text-sm text-critical">
                      {" "}
                      · {weekdayOf(l.date) === 6 ? "שבת" : "חג"}, לבדיקת הרפרנטית
                    </span>
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

      {report.editable && !report.is_manual ? (
        <Link href={`/supplier/new?report=${report.report_id}`} className={buttonClass}>
          תיקון ושליחה מחדש
        </Link>
      ) : null}
    </>
  );
}
