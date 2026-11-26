import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { ReportLines } from "@/components/report-lines";
import { CapBar, Callout, PageHead, Panel, StatusPill, secondaryButtonClass } from "@/components/ui";
import { formatDateTime, formatMoney, monthLabel, plural } from "@/lib/format";
import { getStaffReport } from "@/lib/staff/data";
import { StaffDecisionForm } from "./decision-form";

export const metadata = { title: "דיווח - דיווח הגנים" };

const ACTOR: Record<string, string> = {
  SUPPLIER_CONTACT: "ספק",
  TEACHER: "גננת",
  STAFF: "צוות",
  SYSTEM: "מערכת",
};

export default async function StaffReportPage({ params }: PageProps<"/staff/reports/[id]">) {
  await connection();
  const { id } = await params;
  if (!/^\d{1,9}$/.test(id)) notFound();

  const data = await getStaffReport(Number(id));
  if (!data) notFound();
  const { staff, reasons, report } = data;

  const month = monthLabel(report.year, report.month);
  const doubles = report.lines.filter((l) => l.double).length;
  const latest = report.approvals[0];
  const waitingForMe = report.status === "TEACHER_APPROVED";
  const contentMatches = Boolean(latest && latest.decision === "APPROVED" && latest.content_matches);
  const u = report.usage;

  return (
    <>
      <PageHead
        title={`${report.supplier.name} · ${month}`}
        intro={`${report.kindergarten.name} (${report.kindergarten.code}) · ${report.domain}`}
        action={
          <Link href={waitingForMe ? "/staff/queue" : "/staff/reports"} className={secondaryButtonClass}>
            {waitingForMe ? "חזרה לתור האישורים" : "חזרה לכל הדיווחים"}
          </Link>
        }
      />

      <Panel>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
          <div>
            <dt className="text-sm text-ink-muted">סטטוס</dt>
            <dd className="mt-1">
              <StatusPill status={report.status} label={report.status_name} />
            </dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">מפגשים</dt>
            <dd className="mt-1 tabular-nums text-ink">
              {report.sessions}
              {doubles ? ` (${plural(doubles, "מפגש כפול אחד", "כפולים")})` : ""}
            </dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">סכום</dt>
            <dd className="mt-1 tabular-nums text-ink">{formatMoney(report.amount)}</dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">נשלח על ידי הספק</dt>
            <dd className="mt-1 text-ink">
              {report.submitted_at ? formatDateTime(report.submitted_at) : "לא נשלח"}
              {report.submitted_by ? <span className="block text-sm text-ink-muted">{report.submitted_by}</span> : null}
            </dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">מספר ספק</dt>
            <dd className="mt-1 tabular-nums text-ink">{report.supplier.number}</dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">סוג התקשרות</dt>
            <dd className="mt-1 text-ink">{report.engagement_type}</dd>
          </div>
          <div>
            <dt className="text-sm text-ink-muted">תעריף בחוזה</dt>
            <dd className="mt-1 tabular-nums text-ink">{formatMoney(report.tariff)}</dd>
          </div>
          {report.locked_at ? (
            <div>
              <dt className="text-sm text-ink-muted">אושר סופית ונעל</dt>
              <dd className="mt-1 text-ink">
                {formatDateTime(report.locked_at)}
                {report.final_approved_by ? (
                  <span className="block text-sm text-ink-muted">{report.final_approved_by}</span>
                ) : null}
              </dd>
            </div>
          ) : null}
        </dl>
      </Panel>

      <Panel title="ניצול ההתקשרות (כל הדיווחים שלא נדחו)">
        <CapBar
          label="מפגשים"
          used={u.sessions_used}
          cap={u.session_cap}
          text={`${u.sessions_used} מתוך ${u.session_cap}`}
        />
        <CapBar
          label="סכום"
          used={u.amount_used}
          cap={u.amount_cap}
          text={`${formatMoney(u.amount_used)} מתוך ${formatMoney(u.amount_cap)}`}
        />
        {u.is_blocked ? (
          <p className="text-sm text-critical">ההתקשרות הגיעה לתקרה. אפשר לאשר חריגה במסך התקרות.</p>
        ) : u.is_warning ? (
          <p className="text-sm text-ink-muted">ההתקשרות מתקרבת לתקרה.</p>
        ) : null}
      </Panel>

      <ReportLines lines={report.lines} amount={report.amount} month={month} />

      <Panel title="אישור הגננת">
        {latest ? (
          <>
            <p className="text-ink">
              <strong>{latest.decision === "APPROVED" ? "אושר" : "הוחזר לספק"}</strong> על ידי {latest.teacher_name} ב-
              {formatDateTime(latest.decided_at)}.
              {latest.reason ? ` סיבה: ${latest.reason}.` : ""}
              {latest.comment ? ` ${latest.comment}` : ""}
            </p>
            {latest.decision === "APPROVED" ? (
              latest.content_matches ? (
                <p className="mt-2 text-sm text-success">✓ תוכן הדיווח זהה למה שהגננת אישרה.</p>
              ) : (
                <Callout kind="critical">
                  <p>
                    <strong>תוכן הדיווח השתנה אחרי שהגננת אישרה אותו.</strong> אי אפשר לנעול אותו. יש להחזיר אותו
                    לספק, כדי שיישלח שוב לאישור הגננת.
                  </p>
                </Callout>
              )
            ) : null}
          </>
        ) : (
          <p className="text-ink-muted">
            {report.is_manual || report.kindergarten.is_manual_track
              ? "הגן במסלול טופס ידני, ולכן אין אישור דיגיטלי."
              : "הגננת עדיין לא החליטה על הדיווח."}
          </p>
        )}
      </Panel>

      {waitingForMe ? (
        staff.can_act ? (
          <StaffDecisionForm reportId={report.report_id} reasons={reasons} contentMatches={contentMatches} />
        ) : (
          <Callout kind="info">
            <p>ההרשאה שלך היא צפייה בלבד, ולכן אין כאן אפשרות לאשר או להחזיר.</p>
          </Callout>
        )
      ) : null}

      <Panel title="היסטוריה">
        {report.history.length === 0 ? (
          <p className="text-ink-muted">אין עדיין שינויים בסטטוס.</p>
        ) : (
          <ol className="space-y-3">
            {report.history.map((h, i) => (
              <li key={`${h.at}-${i}`} className="border-s-2 border-line ps-3">
                <p className="text-ink">
                  <strong>{h.to}</strong>
                  {h.from ? <span className="text-ink-muted"> (היה: {h.from})</span> : null}
                </p>
                <p className="text-sm text-ink-muted">
                  {formatDateTime(h.at)} · {ACTOR[h.actor_type] ?? h.actor_type}
                  {h.actor_name ? `: ${h.actor_name}` : ""}
                </p>
                {h.reason || h.comment ? (
                  <p className="text-sm text-ink">
                    {h.reason ? `סיבה: ${h.reason}. ` : ""}
                    {h.comment ?? ""}
                  </p>
                ) : null}
              </li>
            ))}
          </ol>
        )}
      </Panel>
    </>
  );
}
