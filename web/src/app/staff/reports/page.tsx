import Link from "next/link";
import { connection } from "next/server";
import {
  PageHead,
  StatusPill,
  buttonClass,
  secondaryButtonClass,
  stackedBody,
  stackedCell,
  stackedHead,
  stackedRow,
  stackedTable,
} from "@/components/ui";
import { formatDateTime, formatMoney, monthLabel, plural } from "@/lib/format";
import { getStaffReports } from "@/lib/staff/data";
import { applyFilters, filtersQuery, hasFilters, readFilters } from "@/lib/staff/report-filters";
import { STAGES } from "@/lib/staff/types";

export const metadata = { title: "כל הדיווחים - דיווח הגנים" };

const selectClass =
  "w-full rounded-[10px] border border-field-border bg-surface px-3 py-2 text-base text-ink";

export default async function StaffReportsPage({ searchParams }: PageProps<"/staff/reports">) {
  await connection();
  const { reports } = await getStaffReports();
  // Filters come from the URL (a plain GET form), so they work without JavaScript and can be bookmarked.
  const filters = readFilters(await searchParams);
  const { stage, month: monthParam, supplier: supplierParam, garden: gardenParam, mine } = filters;

  const months = [...new Set(reports.map((r) => `${r.year}-${String(r.month).padStart(2, "0")}`))].sort().reverse();
  const suppliers = [...new Map(reports.map((r) => [r.supplier.supplier_id, r.supplier])).values()].sort((a, b) =>
    a.name.localeCompare(b.name, "he"),
  );
  const gardens = [...new Map(reports.map((r) => [r.kindergarten.kindergarten_id, r.kindergarten])).values()].sort(
    (a, b) => a.name.localeCompare(b.name, "he"),
  );
  const anyMine = gardens.some((g) => g.is_mine);

  const list = applyFilters(reports, filters);
  const filtered = hasFilters(filters);
  const total = list.reduce((sum, r) => sum + r.amount, 0);

  return (
    <>
      <PageHead
        title="כל הדיווחים"
        intro="כל הדיווחים מ-12 החודשים האחרונים, וכל דיווח שעדיין פתוח. החדשים קודם."
      />

      <form
        method="get"
        className="mb-5 rounded-[18px] border border-line bg-surface p-4 shadow-card"
        aria-label="סינון הדיווחים"
      >
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <label htmlFor="f-stage" className="mb-1 block text-sm font-medium text-ink">
              שלב
            </label>
            <select id="f-stage" name="stage" defaultValue={stage?.key ?? ""} className={selectClass}>
              <option value="">כל השלבים</option>
              {STAGES.map((s) => (
                <option key={s.key} value={s.key}>
                  {s.label}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="f-month" className="mb-1 block text-sm font-medium text-ink">
              חודש
            </label>
            <select id="f-month" name="month" defaultValue={monthParam ?? ""} className={selectClass}>
              <option value="">כל החודשים</option>
              {months.map((m) => (
                <option key={m} value={m}>
                  {monthLabel(Number(m.slice(0, 4)), Number(m.slice(5, 7)))}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="f-supplier" className="mb-1 block text-sm font-medium text-ink">
              ספק
            </label>
            <select id="f-supplier" name="supplier" defaultValue={supplierParam || ""} className={selectClass}>
              <option value="">כל הספקים</option>
              {suppliers.map((s) => (
                <option key={s.supplier_id} value={s.supplier_id}>
                  {s.name} ({s.number})
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="f-garden" className="mb-1 block text-sm font-medium text-ink">
              גן
            </label>
            <select id="f-garden" name="garden" defaultValue={gardenParam || ""} className={selectClass}>
              <option value="">כל הגנים</option>
              {gardens.map((g) => (
                <option key={g.kindergarten_id} value={g.kindergarten_id}>
                  {g.name} ({g.code})
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-3">
          {anyMine ? (
            <label className="flex cursor-pointer items-center gap-2 text-ink">
              <input
                type="checkbox"
                name="mine"
                value="1"
                defaultChecked={mine}
                className="size-4 accent-[var(--accent)]"
              />
              רק הגנים שלי
            </label>
          ) : null}
          <button type="submit" className={buttonClass}>
            סינון
          </button>
          {filtered ? (
            <Link href="/staff/reports" className={secondaryButtonClass}>
              ניקוי הסינון
            </Link>
          ) : null}
        </div>
      </form>

      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <p className="text-ink-muted" role="status">
          {plural(list.length, "דיווח אחד", "דיווחים")} · {formatMoney(total)}
        </p>
        {list.length ? (
          // A plain link: the browser downloads the file. Not a <Link>, which would try to render it as a page.
          <a href={`/staff/reports/export${filtersQuery(filters)}`} className={secondaryButtonClass} download>
            הורדה לאקסל
          </a>
        ) : null}
      </div>

      {list.length === 0 ? (
        <div className="rounded-[18px] border border-line bg-surface p-6 text-center text-ink-muted shadow-card">
          אין דיווחים שמתאימים לסינון.
        </div>
      ) : (
        <div className="rounded-[18px] border border-line bg-surface p-2 shadow-card sm:p-3">
          <table className={stackedTable}>
            <caption className="sr-only">רשימת הדיווחים</caption>
            <thead className={stackedHead}>
              <tr className="border-b border-line text-sm text-ink-muted">
                <th scope="col" className="px-3 py-2 font-medium">חודש</th>
                <th scope="col" className="px-3 py-2 font-medium">ספק</th>
                <th scope="col" className="px-3 py-2 font-medium">גן</th>
                <th scope="col" className="px-3 py-2 font-medium">מפגשים</th>
                <th scope="col" className="px-3 py-2 font-medium">סכום</th>
                <th scope="col" className="px-3 py-2 font-medium">סטטוס</th>
                <th scope="col" className="px-3 py-2 font-medium">עדכון אחרון</th>
                <th scope="col" className="px-3 py-2 font-medium">
                  <span className="sr-only">פעולות</span>
                </th>
              </tr>
            </thead>
            <tbody className={stackedBody}>
              {list.map((r) => (
                <tr key={r.report_id} className={stackedRow}>
                  <td data-label="חודש" className={stackedCell}>
                    {monthLabel(r.year, r.month)}
                  </td>
                  <td data-label="ספק" className={stackedCell}>
                    {r.supplier.name}
                  </td>
                  <td data-label="גן" className={stackedCell}>
                    {r.kindergarten.name}
                  </td>
                  <td data-label="מפגשים" className={`${stackedCell} tabular-nums`}>
                    {r.sessions}
                  </td>
                  <td data-label="סכום" className={`${stackedCell} tabular-nums`}>
                    {formatMoney(r.amount)}
                  </td>
                  <td data-label="סטטוס" className={stackedCell}>
                    <StatusPill status={r.status} label={r.status_name} />
                  </td>
                  <td data-label="עדכון אחרון" className={`${stackedCell} text-sm`}>
                    {formatDateTime(r.updated_at)}
                  </td>
                  <td className="px-3 py-2 max-sm:block max-sm:px-0 max-sm:pt-2">
                    <Link
                      href={`/staff/reports/${r.report_id}`}
                      className={secondaryButtonClass}
                      aria-label={`פרטים: ${r.supplier.name}, ${r.kindergarten.name}, ${monthLabel(r.year, r.month)}`}
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
