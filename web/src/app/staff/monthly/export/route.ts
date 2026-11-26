import type { NextRequest } from "next/server";
import { money, num, xlsxResponse } from "@/lib/excel";
import { formatDateTime, monthLabel, ymKey } from "@/lib/format";
import { getStaffMonthly } from "@/lib/staff/data";
import { staffExportGate } from "@/lib/staff/export-gate";
import { parseYm, summarizeBySupplier } from "@/lib/staff/monthly";

// GET /staff/monthly/export?month=2026-09: the monthly payment report as an Excel file.
export async function GET(request: NextRequest) {
  const blocked = await staffExportGate(request);
  if (blocked) return blocked;

  const ym = parseYm(request.nextUrl.searchParams.get("month"));
  if (!ym) return new Response("חודש לא תקין", { status: 400 });

  const { reports } = await getStaffMonthly(ym.year, ym.month);
  const suppliers = summarizeBySupplier(reports);
  const label = monthLabel(ym.year, ym.month);

  const total = suppliers.reduce(
    (t, s) => ({
      gardens: t.gardens + s.gardens,
      days: t.days + s.days,
      doubles: t.doubles + s.doubles,
      sessions: t.sessions + s.sessions,
      amount: t.amount + s.amount,
      open: t.open + s.openReports,
    }),
    { gardens: 0, days: 0, doubles: 0, sessions: 0, amount: 0, open: 0 },
  );

  return xlsxResponse(
    [
      {
        name: "לתשלום לפי ספק",
        header: ["מספר ספק", "ספק", "גנים", "ימי פעילות", "מתוכם כפולים", "מפגשים", "לתשלום (₪)", "דיווחים שעוד לא אושרו"],
        widths: [11, 30, 8, 11, 13, 10, 14, 20],
        rows: suppliers.map((s) => [
          s.supplier.number,
          s.supplier.name,
          num(s.gardens),
          num(s.days),
          num(s.doubles),
          num(s.sessions),
          money(s.amount),
          num(s.openReports),
        ]),
        totals: ['סה"כ', "", num(total.gardens), num(total.days), num(total.doubles), num(total.sessions), money(total.amount), num(total.open)],
      },
      {
        name: "פירוט דיווחים",
        header: ["מספר ספק", "ספק", "סמל גן", "גן", "תחום", "סטטוס", "ימי פעילות", "כפולים", "תעריף (₪)", "סכום (₪)", "לתשלום", "אושר סופית על ידי", "ננעל"],
        widths: [11, 26, 9, 22, 16, 18, 11, 8, 11, 12, 9, 20, 18],
        rows: reports.map((r) => [
          r.supplier.number,
          r.supplier.name,
          r.kindergarten.code,
          r.kindergarten.name,
          r.domain,
          r.status_name,
          num(r.days),
          num(r.doubles),
          money(r.tariff),
          money(r.amount),
          r.is_final ? "כן" : "לא",
          r.final_approved_by ?? "",
          r.locked_at ? formatDateTime(r.locked_at) : "",
        ]),
      },
    ],
    `דוח חודשי ${label}.xlsx`,
    `monthly-report-${ymKey(ym.year, ym.month)}.xlsx`,
  );
}
