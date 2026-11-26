// Shape of access.supplier_data (migration 13). Numbers from Postgres numeric
// arrive as JSON numbers.

import type { ReportLine, ReportStatus } from "@/lib/report-types";

export type { ReportLine, ReportStatus };
export { FINAL, IN_PROGRESS, NEEDS_FIX } from "@/lib/report-types";

export type BlockReason = "MANUAL_TRACK" | "NEEDS_SUPERVISOR_APPROVAL";

export type Engagement = {
  engagement_id: number;
  kindergarten: { kindergarten_id: number; code: string; name: string; is_manual_track: boolean };
  teachers: string[];
  domain: string;
  engagement_type: string;
  school_year: { id: number; name: string; start: string; end: string };
  tariff: number;
  session_cap: number;
  amount_cap: number;
  sessions_used: number;
  amount_used: number;
  is_warning: boolean;
  is_blocked: boolean;
  block_reason: BlockReason | null;
};

export type Report = {
  report_id: number;
  engagement_id: number;
  year: number;
  month: number;
  status: ReportStatus;
  status_name: string;
  editable: boolean;
  is_manual: boolean;
  submitted_at: string | null;
  updated_at: string;
  kindergarten: { code: string; name: string };
  domain: string;
  sessions: number;
  amount: number;
  lines: ReportLine[];
  note: { comment: string | null; reason: string | null; by: string; at: string } | null;
};

export type SupplierData = {
  supplier: { supplier_id: number; name: string; supplier_number: string };
  contact: { contact_id: number; full_name: string };
  today: string;
  min_date: string;
  holidays: { date: string; name: string }[];
  engagements: Engagement[];
  reports: Report[];
};

/** One garden in a submission: the full list of dates for each month it touches. */
export type SubmitItem = { engagementId: number; lines: { date: string; double: boolean }[] };

export type SubmitResult =
  | { ok: false; message: string }
  | { ok: false; errors: { engagementId: number; message: string }[] };

export const BLOCK_REASON_TEXT: Record<BlockReason, string> = {
  MANUAL_TRACK: "הגן הזה במסלול טופס ידני. את הדיווח מגישים בטופס הנייר החתום.",
  NEEDS_SUPERVISOR_APPROVAL: "ההתקשרות ממתינה לאישור מפקחת. אחרי שהרפרנטית תתעד את האישור אפשר יהיה לדווח.",
};
