// Report types shared by the role screens (supplier, teacher, staff).

export type ReportStatus =
  | "DRAFT"
  | "SENT_TO_TEACHER"
  | "TEACHER_APPROVED"
  | "TEACHER_REJECTED"
  | "RETURNED"
  | "STAFF_APPROVED"
  | "LOCKED";

export type ReportLine = { date: string; double: boolean; amount: number; flagged: boolean };

export const IN_PROGRESS: ReportStatus[] = ["SENT_TO_TEACHER", "TEACHER_APPROVED"];
export const NEEDS_FIX: ReportStatus[] = ["RETURNED", "TEACHER_REJECTED"];
export const FINAL: ReportStatus[] = ["STAFF_APPROVED", "LOCKED"];
