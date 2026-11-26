// Filters of the staff reports list. They live in the URL (a plain GET form),
// so the page and its Excel export read them the same way.
import { ymKey } from "@/lib/format";
import { STAGES, type StaffReportRow } from "./types";

export type ReportFilters = {
  stage: (typeof STAGES)[number] | undefined;
  month: string | undefined;
  supplier: number;
  garden: number;
  mine: boolean;
};

type Params = Record<string, string | string[] | undefined>;

function one(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function positiveInt(value: string | undefined) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 && n < 2 ** 31 ? n : 0;
}

export function readFilters(params: Params): ReportFilters {
  const month = one(params.month);
  return {
    stage: STAGES.find((s) => s.key === one(params.stage)),
    month: month && /^\d{4}-(0[1-9]|1[0-2])$/.test(month) ? month : undefined,
    supplier: positiveInt(one(params.supplier)),
    garden: positiveInt(one(params.garden)),
    mine: one(params.mine) === "1",
  };
}

export function hasFilters(f: ReportFilters) {
  return Boolean(f.stage || f.month || f.supplier || f.garden || f.mine);
}

export function applyFilters(reports: StaffReportRow[], f: ReportFilters): StaffReportRow[] {
  return reports.filter(
    (r) =>
      (!f.stage || f.stage.statuses.includes(r.status)) &&
      (!f.month || ymKey(r.year, r.month) === f.month) &&
      (!f.supplier || r.supplier.supplier_id === f.supplier) &&
      (!f.garden || r.kindergarten.kindergarten_id === f.garden) &&
      (!f.mine || r.kindergarten.is_mine),
  );
}

/** The same filters as a query string, for links such as the Excel export. */
export function filtersQuery(f: ReportFilters): string {
  const qs = new URLSearchParams();
  if (f.stage) qs.set("stage", f.stage.key);
  if (f.month) qs.set("month", f.month);
  if (f.supplier) qs.set("supplier", String(f.supplier));
  if (f.garden) qs.set("garden", String(f.garden));
  if (f.mine) qs.set("mine", "1");
  const text = qs.toString();
  return text ? `?${text}` : "";
}
