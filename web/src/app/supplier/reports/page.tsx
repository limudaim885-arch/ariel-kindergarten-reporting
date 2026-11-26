import Link from "next/link";
import { connection } from "next/server";
import { Callout, PageHead, StatusPill, buttonClass, secondaryButtonClass } from "@/components/ui";
import { formatMoney, monthLabel, monthLabelOf, plural, ymKey } from "@/lib/format";
import { getSupplierData } from "@/lib/supplier/data";
import { FINAL, IN_PROGRESS, NEEDS_FIX, type Report } from "@/lib/supplier/types";

export const metadata = { title: "הדיווחים שלי - דיווח הגנים" };

const FILTERS = [
  { key: "all", label: "הכל", test: () => true },
  { key: "fix", label: "דורשים תיקון", test: (r: Report) => NEEDS_FIX.includes(r.status) },
  { key: "progress", label: "בתהליך אישור", test: (r: Report) => IN_PROGRESS.includes(r.status) },
  { key: "final", label: "אושרו סופית", test: (r: Report) => FINAL.includes(r.status) },
] as const;

function one(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function hrefFor(filter: string, month: string | null) {
  const qs = new URLSearchParams();
  if (filter !== "all") qs.set("filter", filter);
  if (month) qs.set("month", month);
  const text = qs.toString();
  return text ? `/supplier/reports?${text}` : "/supplier/reports";
}

const chip = "rounded-full border px-3 py-1 text-sm font-medium";
const chipOn = `${chip} border-accent bg-accent-soft text-accent`;
const chipOff = `${chip} border-line-strong text-ink hover:bg-surface-2`;

// Below the sm breakpoint every row becomes a card, with the column name before each value.
const cell =
  "px-3 py-2 align-middle max-sm:flex max-sm:justify-between max-sm:gap-3 max-sm:px-0 max-sm:py-1 max-sm:before:font-medium max-sm:before:text-ink-muted max-sm:before:content-[attr(data-label)]";

export default async function SupplierReportsPage({ searchParams }: PageProps<"/supplier/reports">) {
  await connection();
  const { reports } = await getSupplierData();
  const params = await searchParams;

  const filter = FILTERS.find((f) => f.key === one(params.filter)) ?? FILTERS[0];
  const months = [...new Set(reports.map((r) => ymKey(r.year, r.month)))];
  const monthParam = one(params.month);
  const month = monthParam && months.includes(monthParam) ? monthParam : null;
  const sentParam = one(params.sent);
  const sent = sentParam && /^\d{1,3}$/.test(sentParam) ? Number(sentParam) : 0;

  const shown = reports.filter((r) => filter.test(r) && (!month || ymKey(r.year, r.month) === month));
  const sessions = shown.reduce((s, r) => s + r.sessions, 0);
  const amount = shown.reduce((s, r) => s + r.amount, 0);

  return (
    <>
      <PageHead
        title="הדיווחים שלי"
        intro={`${plural(shown.length, "דיווח אחד", "דיווחים")} · ${plural(sessions, "מפגש אחד", "מפגשים")} · סה"כ ${formatMoney(amount)}`}
        action={
          <Link href="/supplier/new" className={buttonClass}>
            דיווח חדש
          </Link>
        }
      />

      {sent > 0 ? (
        <Callout kind="success" role="status">
          <p>
            <strong>{sent === 1 ? "הדיווח נשלח לחתימת הגננת." : `${sent} דיווחים נשלחו לחתימת הגננות.`}</strong> אפשר
            לעקוב כאן אחרי הסטטוס.
          </p>
        </Callout>
      ) : null}

      <nav aria-label="סינון לפי מצב" className="mb-3 flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <Link
            key={f.key}
            href={hrefFor(f.key, month)}
            aria-current={f.key === filter.key ? "page" : undefined}
            className={f.key === filter.key ? chipOn : chipOff}
          >
            {f.label} ({reports.filter(f.test).length})
          </Link>
        ))}
      </nav>

      {months.length > 1 ? (
        <nav aria-label="סינון לפי חודש" className="mb-5 flex flex-wrap gap-2">
          <Link
            href={hrefFor(filter.key, null)}
            aria-current={!month ? "page" : undefined}
            className={!month ? chipOn : chipOff}
          >
            כל החודשים
          </Link>
          {months.map((m) => (
            <Link
              key={m}
              href={hrefFor(filter.key, m)}
              aria-current={m === month ? "page" : undefined}
              className={m === month ? chipOn : chipOff}
            >
              {monthLabelOf(m)}
            </Link>
          ))}
        </nav>
      ) : null}

      {shown.length === 0 ? (
        <div className="rounded-[18px] border border-line bg-surface p-6 text-center text-ink-muted shadow-card">
          {reports.length === 0 ? "עדיין לא נשלחו דיווחים." : "אין דיווחים שמתאימים לסינון."}
        </div>
      ) : (
        <div className="rounded-[18px] border border-line bg-surface p-2 shadow-card sm:p-3">
          <table className="w-full text-right max-sm:block">
            <caption className="sr-only">הדיווחים שלך, החדשים קודם</caption>
            <thead className="max-sm:sr-only">
              <tr className="border-b border-line text-sm text-ink-muted">
                <th scope="col" className="px-3 py-2 font-medium">חודש</th>
                <th scope="col" className="px-3 py-2 font-medium">גן</th>
                <th scope="col" className="px-3 py-2 font-medium">תחום</th>
                <th scope="col" className="px-3 py-2 font-medium">מפגשים</th>
                <th scope="col" className="px-3 py-2 font-medium">סכום</th>
                <th scope="col" className="px-3 py-2 font-medium">סטטוס</th>
                <th scope="col" className="px-3 py-2 font-medium">
                  <span className="sr-only">פעולות</span>
                </th>
              </tr>
            </thead>
            <tbody className="max-sm:block">
              {shown.map((r) => (
                <tr
                  key={r.report_id}
                  className="border-b border-line last:border-0 max-sm:mb-2 max-sm:block max-sm:rounded-xl max-sm:border max-sm:p-3 max-sm:last:border"
                >
                  <td data-label="חודש" className={cell}>
                    {monthLabel(r.year, r.month)}
                  </td>
                  <td data-label="גן" className={cell}>
                    {r.kindergarten.name}
                  </td>
                  <td data-label="תחום" className={cell}>
                    {r.domain}
                  </td>
                  <td data-label="מפגשים" className={`${cell} tabular-nums`}>
                    {r.sessions}
                  </td>
                  <td data-label="סכום" className={`${cell} tabular-nums`}>
                    {formatMoney(r.amount)}
                  </td>
                  <td data-label="סטטוס" className={cell}>
                    <StatusPill status={r.status} label={r.status_name} />
                  </td>
                  <td className="px-3 py-2 max-sm:block max-sm:px-0 max-sm:pt-2">
                    <div className="flex flex-wrap gap-2">
                      <Link
                        href={`/supplier/reports/${r.report_id}`}
                        className={secondaryButtonClass}
                        aria-label={`פרטים: ${r.kindergarten.name}, ${monthLabel(r.year, r.month)}`}
                      >
                        פרטים
                      </Link>
                      {r.editable && !r.is_manual ? (
                        <Link
                          href={`/supplier/new?report=${r.report_id}`}
                          className={secondaryButtonClass}
                          aria-label={`תיקון ושליחה מחדש: ${r.kindergarten.name}, ${monthLabel(r.year, r.month)}`}
                        >
                          תיקון ושליחה מחדש
                        </Link>
                      ) : null}
                    </div>
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
