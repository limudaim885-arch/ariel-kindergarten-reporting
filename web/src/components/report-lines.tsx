import { Callout, Panel } from "@/components/ui";
import { formatDateLong, formatMoney, weekdayOf } from "@/lib/format";
import type { ReportLine } from "@/lib/report-types";

/** The reported days of one report, with a warning for Saturdays and holidays. */
export function ReportLines({ lines, amount, month }: { lines: ReportLine[]; amount: number; month: string }) {
  const flagged = lines.filter((l) => l.flagged).length;
  return (
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
          {lines.map((l) => (
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
            <td className="pt-3 text-left tabular-nums">{formatMoney(amount)}</td>
          </tr>
        </tfoot>
      </table>
    </Panel>
  );
}
