import { connection } from "next/server";
import { CapBar, Callout, PageHead } from "@/components/ui";
import { formatDateTime, formatMoney } from "@/lib/format";
import { getStaffCaps } from "@/lib/staff/data";
import { OverrideForm } from "./override-form";

export const metadata = { title: "תקרות וחריגות - דיווח הגנים" };

export default async function StaffCaps({ searchParams }: PageProps<"/staff/caps">) {
  await connection();
  const { staff, engagements } = await getStaffCaps();
  const done = (await searchParams).done === "1";

  return (
    <>
      <PageHead
        title="תקרות וחריגות"
        intro="התקשרויות שהגיעו לתקרה, או שנותרו בהן 3 מפגשים או פחות. ספק שהגיע לתקרה לא יכול לדווח עד שמאשרים חריגה."
      />

      {done ? (
        <Callout kind="success" role="status">
          <p>
            <strong>החריגה נשמרה, והתקרה של ההתקשרות עודכנה.</strong>
          </p>
        </Callout>
      ) : null}

      {!staff.can_act ? (
        <Callout kind="info">
          <p>ההרשאה שלך היא צפייה בלבד, ולכן אין כאן אפשרות לאשר חריגות.</p>
        </Callout>
      ) : null}

      {engagements.length === 0 ? (
        <div className="rounded-[18px] border border-line bg-surface p-6 text-center text-ink-muted shadow-card">
          אין כרגע התקשרויות שמתקרבות לתקרה.
        </div>
      ) : (
        <ul className="grid gap-4 lg:grid-cols-2">
          {engagements.map((e) => {
            const label = `${e.supplier.name}, ${e.kindergarten.name}`;
            return (
              <li key={e.engagement_id} className="rounded-[18px] border border-line bg-surface p-5 shadow-card">
                <div className="mb-3 flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <h2 className="font-semibold text-ink">{e.supplier.name}</h2>
                    <p className="text-sm text-ink-muted">
                      {e.kindergarten.name} ({e.kindergarten.code}) · {e.domain} · {e.engagement_type}
                      {e.kindergarten.is_mine ? " · הגן שלך" : ""}
                    </p>
                  </div>
                  <span
                    className={`rounded-full px-2.5 py-0.5 text-sm font-medium ${
                      e.is_blocked ? "bg-critical-soft text-critical" : "bg-warning-soft text-warning"
                    }`}
                  >
                    {e.is_blocked ? "הגיע לתקרה" : "מתקרב לתקרה"}
                  </span>
                </div>

                <CapBar
                  label="מפגשים"
                  used={e.sessions_used}
                  cap={e.session_cap}
                  text={`${e.sessions_used} מתוך ${e.session_cap}`}
                />
                <CapBar
                  label="סכום"
                  used={e.amount_used}
                  cap={e.amount_cap}
                  text={`${formatMoney(e.amount_used)} מתוך ${formatMoney(e.amount_cap)}`}
                />

                {e.overrides.length ? (
                  <div className="mt-3">
                    <h3 className="text-sm font-medium text-ink">חריגות שכבר אושרו</h3>
                    <ul className="mt-1 space-y-1 text-sm text-ink-muted">
                      {e.overrides.map((o, i) => (
                        <li key={`${o.approved_at}-${i}`}>
                          {[
                            o.extra_sessions ? `+${o.extra_sessions} מפגשים` : null,
                            o.extra_amount ? `+${formatMoney(o.extra_amount)}` : null,
                          ]
                            .filter(Boolean)
                            .join(", ")}{" "}
                          · {o.reason} · {o.approved_by ?? "צוות"}, {formatDateTime(o.approved_at)}
                        </li>
                      ))}
                    </ul>
                  </div>
                ) : null}

                {staff.can_act ? (
                  <div className="mt-4">
                    <OverrideForm engagementId={e.engagement_id} tariff={e.tariff} label={label} />
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
    </>
  );
}
