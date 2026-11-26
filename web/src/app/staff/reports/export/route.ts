import type { NextRequest } from "next/server";
import { money, num, xlsxResponse } from "@/lib/excel";
import { formatDateTime, monthLabel } from "@/lib/format";
import { getStaffReports } from "@/lib/staff/data";
import { staffExportGate } from "@/lib/staff/export-gate";
import { applyFilters, readFilters } from "@/lib/staff/report-filters";

// GET /staff/reports/export?<same filters as the list>: the filtered reports list as an Excel file.
export async function GET(request: NextRequest) {
  const blocked = await staffExportGate(request);
  if (blocked) return blocked;

  const filters = readFilters(Object.fromEntries(request.nextUrl.searchParams));
  const { today, reports } = await getStaffReports();
  const list = applyFilters(reports, filters);

  return xlsxResponse(
    [
      {
        name: "דיווחים",
        header: ["חודש", "מספר ספק", "ספק", "סמל גן", "גן", "תחום", "מפגשים", "סכום (₪)", "סטטוס", "אישור הגננת", "עדכון אחרון"],
        widths: [14, 11, 26, 9, 22, 16, 9, 12, 18, 28, 18],
        rows: list.map((r) => [
          monthLabel(r.year, r.month),
          r.supplier.number,
          r.supplier.name,
          r.kindergarten.code,
          r.kindergarten.name,
          r.domain,
          num(r.sessions),
          money(r.amount),
          r.status_name,
          r.teacher_decision
            ? `${r.teacher_decision.decision === "APPROVED" ? "אישרה" : "החזירה"}: ${r.teacher_decision.teacher_name}, ${formatDateTime(r.teacher_decision.decided_at)}`
            : "",
          formatDateTime(r.updated_at),
        ]),
        totals: ['סה"כ', "", "", "", "", "", num(list.reduce((s, r) => s + r.sessions, 0)), money(list.reduce((s, r) => s + r.amount, 0)), "", "", ""],
      },
    ],
    `דיווחים ${today}.xlsx`,
    `reports-${today}.xlsx`,
  );
}
