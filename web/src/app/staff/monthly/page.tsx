import Link from "next/link";
import { connection } from "next/server";
import {
  Callout,
  PageHead,
  Panel,
  StatCard,
  StatusPill,
  buttonClass,
  secondaryButtonClass,
  stackedBody,
  stackedCell,
  stackedHead,
  stackedRow,
  stackedTable,
} from "@/components/ui";
import { formatDateTime, formatMoney, monthLabel, plural, ymKey } from "@/lib/format";
import { getStaffMonthly, getStaffReports } from "@/lib/staff/data";
import { parseYm, previousMonth, summarizeBySupplier } from "@/lib/staff/monthly";
import { PrintButton } from "./print-button";

export const metadata = { title: "דוח חודשי - דיווח הגנים" };

export default async function StaffMonthly({ searchParams }: PageProps<"/staff/monthly">) {
  await connection();
  const params = await searchParams;
  const { staff, today } = await getStaffReports();
  // Default: last month, the month that is usually paid for now.
  const ym = parseYm(typeof params.month === "string" ? params.month : undefined) ?? previousMonth(today);
  const data = await getStaffMonthly(ym.year, ym.month);

  const label = monthLabel(ym.year, ym.month);
  const key = ymKey(ym.year, ym.month);
  const suppliers = summarizeBySupplier(data.reports);
  const paid = suppliers.filter((s) => s.finalReports > 0);
  const open = data.reports.filter((r) => !r.is_final);
  const totalAmount = suppliers.reduce((sum, s) => sum + s.amount, 0);
  const totalSessions = suppliers.reduce((sum, s) => sum + s.sessions, 0);
  const finalCount = data.reports.length - open.length;

  // The month list always includes the chosen month, even with no reports yet.
  const months = data.months.some((m) => m.year === ym.year && m.month === ym.month)
    ? data.months
    : [{ year: ym.year, month: ym.month, reports: 0 }, ...data.months];

  return (
    <>
      <p className="mb-2 hidden text-sm text-black print:block">
        החברה העירונית אריאל · מערכת דיווח הגנים · הופק ב-{formatDateTime(new Date().toISOString())} על ידי {staff.full_name}
      </p>
      <PageHead
        title={`דוח חודשי לתשלום · ${label}`}
        intro="לפי חודש הפעילות. הסכום לתשלום כולל רק דיווחים שאושרו סופית וננעלו."
        action={
          <div className="flex flex-wrap gap-2 print:hidden">
            {data.reports.length ? (
              // A plain link: the browser downloads the file.
              <a href={`/staff/monthly/export?month=${key}`} className={buttonClass} download>
                הורדה לאקסל
              </a>
            ) : null}
            <PrintButton />
          </div>
        }
      />

      <form method="get" className="mb-5 flex flex-wrap items-end gap-3 print:hidden" aria-label="בחירת חודש">
        <div>
          <label htmlFor="m-month" className="mb-1 block text-sm font-medium text-ink">
            חודש פעילות
          </label>
          <select
            id="m-month"
            name="month"
            defaultValue={key}
            className="rounded-[10px] border border-field-border bg-surface px-3 py-2 text-base text-ink"
          >
            {months.map((m) => (
              <option key={ymKey(m.year, m.month)} value={ymKey(m.year, m.month)}>
                {monthLabel(m.year, m.month)} ({plural(m.reports, "דיווח אחד", "דיווחים")})
              </option>
            ))}
          </select>
        </div>
        <button type="submit" className={secondaryButtonClass}>
          הצגה
        </button>
      </form>

      <div className="mb-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard title="ספקים לתשלום" value={paid.length} />
        <StatCard title="דיווחים" value={data.reports.length} sub={`${finalCount} אושרו וננעלו`} />
        <StatCard title="מפגשים מאושרים" value={totalSessions} />
        <StatCard title='סה"כ לתשלום' value={formatMoney(totalAmount)} accent />
      </div>

      {open.length ? (
        <Callout kind="warning">
          <p>
            {plural(open.length, "דיווח אחד", "דיווחים")} על {label} עוד לא אושרו סופית, ולכן לא נכללים בסכום לתשלום.
            הם מופיעים בסוף הדף.
          </p>
        </Callout>
      ) : null}

      <Panel title="פירוט לפי ספק">
        {suppliers.length === 0 ? (
          <p className="text-ink-muted">אין דיווחים על {label}.</p>
        ) : (
          <table className={stackedTable}>
            <caption className="sr-only">סכום לתשלום לכל ספק על {label}</caption>
            <thead className={stackedHead}>
              <tr className="border-b border-line text-sm text-ink-muted">
                <th scope="col" className="px-3 py-2 font-medium">ספק</th>
                <th scope="col" className="px-3 py-2 font-medium">מספר ספק</th>
                <th scope="col" className="px-3 py-2 font-medium">גנים</th>
                <th scope="col" className="px-3 py-2 font-medium">ימי פעילות</th>
                <th scope="col" className="px-3 py-2 font-medium">מתוכם כפולים</th>
                <th scope="col" className="px-3 py-2 font-medium">לתשלום</th>
                <th scope="col" className="px-3 py-2 font-medium">טרם אושרו</th>
              </tr>
            </thead>
            <tbody className={stackedBody}>
              {suppliers.map((s) => (
                <tr key={s.supplier.supplier_id} className={stackedRow}>
                  <td data-label="ספק" className={stackedCell}>
                    {s.supplier.name}
                  </td>
                  <td data-label="מספר ספק" className={`${stackedCell} tabular-nums`}>
                    {s.supplier.number}
                  </td>
                  <td data-label="גנים" className={`${stackedCell} tabular-nums`}>
                    {s.gardens}
                  </td>
                  <td data-label="ימי פעילות" className={`${stackedCell} tabular-nums`}>
                    {s.days}
                  </td>
                  <td data-label="מתוכם כפולים" className={`${stackedCell} tabular-nums`}>
                    {s.doubles}
                  </td>
                  <td data-label="לתשלום" className={`${stackedCell} font-semibold tabular-nums`}>
                    {formatMoney(s.amount)}
                  </td>
                  <td data-label="טרם אושרו" className={`${stackedCell} tabular-nums`}>
                    {s.openReports}
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot className="max-sm:block">
              <tr className="font-semibold text-ink max-sm:flex max-sm:justify-between max-sm:pt-2">
                <td className="px-3 pt-3 max-sm:px-0" colSpan={5}>
                  סה&quot;כ לתשלום
                </td>
                <td className="px-3 pt-3 tabular-nums max-sm:px-0">{formatMoney(totalAmount)}</td>
                <td className="px-3 pt-3 max-sm:hidden" />
              </tr>
            </tfoot>
          </table>
        )}
      </Panel>

      {open.length ? (
        <Panel title={`עוד לא אושרו סופית (${open.length})`}>
          <ul className="space-y-2">
            {open.map((r) => (
              <li key={r.report_id} className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-2 last:border-0">
                <span className="text-ink">
                  {r.supplier.name} · {r.kindergarten.name} · {formatMoney(r.amount)}
                </span>
                <span className="flex items-center gap-2">
                  <StatusPill status={r.status} label={r.status_name} />
                  <Link
                    href={`/staff/reports/${r.report_id}`}
                    className="text-sm font-medium text-accent underline underline-offset-2 print:hidden"
                    aria-label={`פרטים: ${r.supplier.name}, ${r.kindergarten.name}`}
                  >
                    פרטים
                  </Link>
                </span>
              </li>
            ))}
          </ul>
        </Panel>
      ) : null}
    </>
  );
}
