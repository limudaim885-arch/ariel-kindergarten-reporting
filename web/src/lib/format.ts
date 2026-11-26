// Formatting for Hebrew screens. Dates are "YYYY-MM-DD" strings and are read
// as calendar days (UTC), so the server and the browser always agree.

export const HE_MONTHS = [
  "ינואר", "פברואר", "מרץ", "אפריל", "מאי", "יוני",
  "יולי", "אוגוסט", "ספטמבר", "אוקטובר", "נובמבר", "דצמבר",
] as const;

export const HE_WEEKDAYS = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"] as const;

const moneyFormat = new Intl.NumberFormat("he-IL", {
  style: "currency",
  currency: "ILS",
  maximumFractionDigits: 2,
  minimumFractionDigits: 0,
});

const dateTimeFormat = new Intl.DateTimeFormat("he-IL", {
  timeZone: "Asia/Jerusalem",
  day: "numeric",
  month: "numeric",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

export function formatMoney(amount: number): string {
  return moneyFormat.format(amount);
}

/** "2026-11" for a "YYYY-MM-DD" date. */
export function ymOf(date: string): string {
  return date.slice(0, 7);
}

export function ymKey(year: number, month: number): string {
  return `${year}-${String(month).padStart(2, "0")}`;
}

/** "נובמבר 2026" */
export function monthLabel(year: number, month: number): string {
  return `${HE_MONTHS[month - 1]} ${year}`;
}

export function monthLabelOf(ym: string): string {
  return monthLabel(Number(ym.slice(0, 4)), Number(ym.slice(5, 7)));
}

/** Moves a "YYYY-MM" key by n months. */
export function addMonths(ym: string, n: number): string {
  const total = Number(ym.slice(0, 4)) * 12 + Number(ym.slice(5, 7)) - 1 + n;
  return ymKey(Math.floor(total / 12), (total % 12) + 1);
}

/** 0 = Sunday ... 6 = Saturday */
export function weekdayOf(date: string): number {
  const [y, m, d] = date.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

export function daysInMonth(ym: string): number {
  const [y, m] = ym.split("-").map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** "3.11.2026" */
export function formatDate(date: string): string {
  const [y, m, d] = date.split("-").map(Number);
  return `${d}.${m}.${y}`;
}

/** "יום שלישי, 3 בנובמבר 2026" */
export function formatDateLong(date: string): string {
  const [y, m, d] = date.split("-").map(Number);
  return `יום ${HE_WEEKDAYS[weekdayOf(date)]}, ${d} ב${HE_MONTHS[m - 1]} ${y}`;
}

/** Timestamp from the database, shown in Israel time. */
export function formatDateTime(timestamp: string): string {
  return dateTimeFormat.format(new Date(timestamp));
}

export function plural(n: number, one: string, many: string): string {
  return n === 1 ? one : `${n} ${many}`;
}
