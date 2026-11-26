// Helpers shared by the monthly report page and its Excel export.
import { addMonths, ymKey } from "@/lib/format";
import type { MonthlyReport } from "./types";

export type SupplierSummary = {
  supplier: MonthlyReport["supplier"];
  /** Kindergartens with a payable report this month. */
  gardens: number;
  days: number;
  doubles: number;
  sessions: number;
  /** Payable: approved by staff or locked. */
  amount: number;
  finalReports: number;
  /** Sent but not yet approved by staff. */
  openReports: number;
};

const YM_PATTERN = /^(\d{4})-(0[1-9]|1[0-2])$/;

/** "2026-09" to { year, month }, or null for anything else. */
export function parseYm(value: string | null | undefined): { year: number; month: number } | null {
  const m = typeof value === "string" ? YM_PATTERN.exec(value) : null;
  if (!m) return null;
  const year = Number(m[1]);
  if (year < 2020 || year > 2100) return null;
  return { year, month: Number(m[2]) };
}

/** The month before today's: the usual month to pay for. */
export function previousMonth(today: string): { year: number; month: number } {
  return parseYm(addMonths(today.slice(0, 7), -1))!;
}

export function summarizeBySupplier(reports: MonthlyReport[]): SupplierSummary[] {
  const map = new Map<number, SupplierSummary & { gardenIds: Set<number> }>();
  for (const r of reports) {
    let s = map.get(r.supplier.supplier_id);
    if (!s) {
      s = {
        supplier: r.supplier,
        gardens: 0,
        days: 0,
        doubles: 0,
        sessions: 0,
        amount: 0,
        finalReports: 0,
        openReports: 0,
        gardenIds: new Set(),
      };
      map.set(r.supplier.supplier_id, s);
    }
    if (r.is_final) {
      s.gardenIds.add(r.kindergarten.kindergarten_id);
      s.days += r.days;
      s.doubles += r.doubles;
      s.sessions += r.sessions;
      s.amount += r.amount;
      s.finalReports += 1;
    } else {
      s.openReports += 1;
    }
  }
  return [...map.values()]
    .map(({ gardenIds, ...s }) => ({ ...s, gardens: gardenIds.size }))
    .sort((a, b) => b.amount - a.amount || a.supplier.name.localeCompare(b.supplier.name, "he"));
}

export function monthHref(year: number, month: number) {
  return `/staff/monthly?month=${ymKey(year, month)}`;
}
