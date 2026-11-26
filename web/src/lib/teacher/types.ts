// Shape of access.teacher_data (migration 14).
import type { ReportLine, ReportStatus } from "@/lib/report-types";

export type TeacherDecision = {
  decision: "APPROVED" | "REJECTED";
  decided_at: string;
  teacher_name: string;
  reason: string | null;
  comment: string | null;
};

export type TeacherReport = {
  report_id: number;
  year: number;
  month: number;
  status: ReportStatus;
  status_name: string;
  is_manual: boolean;
  submitted_at: string | null;
  kindergarten: { kindergarten_id: number; code: string; name: string; is_manual_track: boolean };
  supplier: { name: string };
  domain: string;
  engagement_type: string;
  tariff: number;
  sessions: number;
  amount: number;
  lines: ReportLine[];
  decision: TeacherDecision | null;
};

export type TeacherData = {
  teacher: { teacher_id: number; full_name: string };
  today: string;
  kindergartens: { kindergarten_id: number; code: string; name: string; is_manual_track: boolean; is_substitute: boolean }[];
  reasons: { id: number; name: string }[];
  reports: TeacherReport[];
};

/** Waiting for this teacher's signature in the app (not the paper-form track). */
export function isPending(r: TeacherReport) {
  return r.status === "SENT_TO_TEACHER" && !r.is_manual && !r.kindergarten.is_manual_track;
}

export type DecideInput = {
  reportId: number;
  decision: "APPROVED" | "REJECTED";
  reasonId: number | null;
  comment: string;
  /** The "אני מאשרת" checkbox; must be true to approve. */
  confirmed: boolean;
};
