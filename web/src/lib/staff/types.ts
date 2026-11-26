// Shapes of the staff functions in migration 16 (access.staff_*).
import type { ReportLine, ReportStatus } from "@/lib/report-types";

export type StaffMember = {
  staff_user_id: number;
  full_name: string;
  role_code: "ADMIN" | "REFERENT" | "VIEWER";
  /** ADMIN and REFERENT approve, lock and add cap exceptions. VIEWER only reads. */
  can_act: boolean;
};

type Kindergarten = { kindergarten_id: number; code: string; name: string; is_mine: boolean };
type Supplier = { supplier_id: number; number: string; name: string };

export type StaffReportRow = {
  report_id: number;
  year: number;
  month: number;
  status: ReportStatus;
  status_name: string;
  is_manual: boolean;
  submitted_at: string | null;
  updated_at: string;
  kindergarten: Kindergarten & { is_manual_track: boolean };
  supplier: Supplier;
  domain: string;
  sessions: number;
  amount: number;
  teacher_decision: { decision: "APPROVED" | "REJECTED"; decided_at: string; teacher_name: string } | null;
};

export type StaffReportsData = { staff: StaffMember; today: string; reports: StaffReportRow[] };

export type StaffReportDetail = {
  report_id: number;
  year: number;
  month: number;
  status: ReportStatus;
  status_name: string;
  is_manual: boolean;
  submitted_at: string | null;
  final_approved_at: string | null;
  final_approved_by: string | null;
  locked_at: string | null;
  kindergarten: Kindergarten & { is_manual_track: boolean };
  supplier: Supplier;
  submitted_by: string | null;
  domain: string;
  engagement_type: string;
  engagement_id: number;
  tariff: number;
  usage: {
    session_cap: number;
    sessions_used: number;
    amount_cap: number;
    amount_used: number;
    is_warning: boolean;
    is_blocked: boolean;
  };
  sessions: number;
  amount: number;
  lines: ReportLine[];
  approvals: {
    decision: "APPROVED" | "REJECTED";
    decided_at: string;
    teacher_name: string;
    reason: string | null;
    comment: string | null;
    /** The report lines still hash to what the teacher saw when she decided. */
    content_matches: boolean;
  }[];
  history: {
    at: string;
    from: string | null;
    to: string;
    actor_type: "SUPPLIER_CONTACT" | "TEACHER" | "STAFF" | "SYSTEM";
    actor_name: string | null;
    reason: string | null;
    comment: string | null;
  }[];
};

export type StaffReportData = {
  staff: StaffMember;
  reasons: { id: number; name: string }[];
  report: StaffReportDetail;
};

export type CapEngagement = {
  engagement_id: number;
  supplier: Supplier;
  kindergarten: Kindergarten;
  domain: string;
  engagement_type: string;
  tariff: number;
  session_cap: number;
  sessions_used: number;
  amount_cap: number;
  amount_used: number;
  is_warning: boolean;
  is_blocked: boolean;
  overrides: {
    extra_sessions: number | null;
    extra_amount: number | null;
    reason: string;
    approved_at: string;
    approved_by: string | null;
  }[];
};

export type StaffCapsData = { staff: StaffMember; engagements: CapEngagement[] };

/** Where a report is and who holds it. Each status belongs to exactly one stage. */
export const STAGES = [
  {
    key: "teacher",
    label: "ממתינים לחתימת גננת",
    holder: "אצל הגננת",
    statuses: ["SENT_TO_TEACHER"] as ReportStatus[],
  },
  {
    key: "queue",
    label: "ממתינים לאישור סופי",
    holder: "אצל הצוות, בתור האישורים",
    statuses: ["TEACHER_APPROVED"] as ReportStatus[],
  },
  {
    key: "returned",
    label: "הוחזרו לספק לתיקון",
    holder: "אצל הספק",
    statuses: ["TEACHER_REJECTED", "RETURNED"] as ReportStatus[],
  },
  {
    key: "final",
    label: "אושרו ונעלו",
    holder: "סגור, מוכן לתשלום",
    statuses: ["STAFF_APPROVED", "LOCKED"] as ReportStatus[],
  },
] as const;

export type StageKey = (typeof STAGES)[number]["key"];

export type DecideInput = {
  reportId: number;
  decision: "APPROVE" | "RETURN";
  reasonId: number | null;
  comment: string;
  /** The "בדקתי ואני מאשרת" checkbox; must be true to approve and lock. */
  confirmed: boolean;
};

export type CapOverrideInput = {
  engagementId: number;
  extraSessions: number;
  extraAmount: number;
  reason: string;
};

export type MonthlyReport = {
  report_id: number;
  status: ReportStatus;
  status_name: string;
  /** Approved by staff or locked: counted for payment. */
  is_final: boolean;
  supplier: Supplier;
  kindergarten: Kindergarten;
  domain: string;
  tariff: number;
  days: number;
  doubles: number;
  sessions: number;
  amount: number;
  locked_at: string | null;
  final_approved_by: string | null;
};

export type StaffMonthlyData = {
  staff: StaffMember;
  year: number;
  month: number;
  months: { year: number; month: number; reports: number }[];
  reports: MonthlyReport[];
};

export type MetricsMonth = {
  year: number;
  month: number;
  reports: number;
  final: number;
  avg_days_to_final: number | null;
  max_days_to_final: number | null;
  teacher_approved: number;
  avg_days_to_teacher: number | null;
  teacher_within_5_days: number;
  approved: number;
  digital: number;
  bounced: number;
};

export type StaffMetricsData = {
  staff: StaffMember;
  today: string;
  months: MetricsMonth[];
  suppliers: { supplier_id: number; number: string; name: string; reports: number; bounced: number }[];
};
