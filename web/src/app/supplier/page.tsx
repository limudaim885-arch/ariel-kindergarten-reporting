import Link from "next/link";
import { connection } from "next/server";
import { Callout, CapBar, PageHead, Panel, StatCard, StatusPill, buttonClass, secondaryButtonClass } from "@/components/ui";
import { addMonths, formatDate, formatMoney, monthLabelOf, plural, ymKey, ymOf } from "@/lib/format";
import { getSupplierData } from "@/lib/supplier/data";
import { BLOCK_REASON_TEXT, FINAL, IN_PROGRESS, NEEDS_FIX, type Report } from "@/lib/supplier/types";

export const metadata = { title: "בית - דיווח הגנים" };

export default async function SupplierHome() {
  await connection();
  const data = await getSupplierData();
  const { engagements, reports, supplier } = data;

  const inProgress = reports.filter((r) => IN_PROGRESS.includes(r.status));
  const needsFix = reports.filter((r) => NEEDS_FIX.includes(r.status));
  const final = reports.filter((r) => FINAL.includes(r.status));
  const finalAmount = final.reduce((sum, r) => sum + r.amount, 0);

  const thisMonth = ymOf(data.today);
  const lastMonth = addMonths(thisMonth, -1);
  const byMonth = new Map<string, Report>(
    reports.map((r) => [`${r.engagement_id}:${ymKey(r.year, r.month)}`, r]),
  );

  const blocked = engagements.filter((e) => !e.block_reason && e.is_blocked);
  const nearCap = engagements.filter((e) => !e.block_reason && !e.is_blocked && e.is_warning);

  return (
    <>
      <PageHead
        title={`שלום, ${supplier.name}`}
        intro={`מספר ספק ${supplier.supplier_number}. כאן רואים את הגנים שלך ואת מצב הדיווחים.`}
        action={
          <Link href="/supplier/new" className={buttonClass}>
            דיווח חדש
          </Link>
        }
      />

      {needsFix.length > 0 && (
        <Callout kind="critical">
          <p>
            <strong>
              {needsFix.length === 1 ? "דיווח אחד הוחזר לתיקון." : `${needsFix.length} דיווחים הוחזרו לתיקון.`}
            </strong>{" "}
            <Link href="/supplier/reports?filter=fix" className="font-medium underline underline-offset-2">
              לצפייה בהערות ולשליחה מחדש
            </Link>
          </p>
        </Callout>
      )}

      {blocked.map((e) => (
        <Callout key={`b${e.engagement_id}`} kind="critical">
          <p>
            <strong>ב{e.kindergarten.name} הגעת לתקרת ההתקשרות ({e.domain}).</strong> לדיווח על מפגשים נוספים
            יש לפנות לרפרנטית, והיא תאשר חריגה במערכת.
          </p>
        </Callout>
      ))}

      {nearCap.map((e) => (
        <Callout key={`w${e.engagement_id}`} kind="warning">
          <p>
            <strong>מתקרבים לתקרה ב{e.kindergarten.name}:</strong> נותרו{" "}
            {plural(Math.max(e.session_cap - e.sessions_used, 0), "מפגש אחד", "מפגשים")} ו-
            {formatMoney(Math.max(e.amount_cap - e.amount_used, 0))}.
          </p>
        </Callout>
      ))}

      <div className="mb-5 grid gap-3 sm:grid-cols-3">
        <StatCard title="בתהליך אישור" value={inProgress.length} sub="נשלחו וממתינים לגננת או לרפרנטית" />
        <StatCard title="דורשים תיקון" value={needsFix.length} sub="הוחזרו אליך עם הערה" />
        <StatCard title="אושרו סופית" value={final.length} sub={`סה"כ ${formatMoney(finalAmount)}`} accent />
      </div>

      <Panel title="הגנים שלך">
        <p className="mb-4 text-sm text-ink-muted">
          אפשר לדווח על תאריכים מ-{formatDate(data.min_date)} ועד היום. לדיווח על תאריך מוקדם יותר יש לפנות
          לרפרנטית.
        </p>

        {engagements.length === 0 ? (
          <Callout kind="info">
            <p>עדיין לא שויכו אליך גנים בשנת הלימודים הנוכחית. יש לפנות לרפרנטית.</p>
          </Callout>
        ) : (
          <ul className="grid gap-3 md:grid-cols-2">
            {engagements.map((e) => {
              const last = byMonth.get(`${e.engagement_id}:${lastMonth}`);
              const current = byMonth.get(`${e.engagement_id}:${thisMonth}`);
              return (
                <li key={e.engagement_id} className="rounded-[14px] border border-line p-4">
                  <div className="mb-3 flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <h3 className="font-semibold text-ink">{e.kindergarten.name}</h3>
                      <p className="text-sm text-ink-muted">
                        סמל גן <span className="tabular-nums">{e.kindergarten.code}</span> · {e.domain} ·{" "}
                        {e.teachers.length ? e.teachers.join(", ") : "אין גננת משובצת"}
                      </p>
                    </div>
                    {e.block_reason ? null : e.is_blocked ? (
                      <StatusPill status="RETURNED" label="הגעת לתקרה" />
                    ) : (
                      <Link
                        href={`/supplier/new?engagement=${e.engagement_id}`}
                        className={secondaryButtonClass}
                        aria-label={`דיווח על ${e.kindergarten.name}, ${e.domain}`}
                      >
                        דיווח
                      </Link>
                    )}
                  </div>

                  {e.block_reason ? (
                    <p className="mb-3 rounded-lg bg-surface-2 px-3 py-2 text-sm text-ink-muted">
                      {BLOCK_REASON_TEXT[e.block_reason]}
                    </p>
                  ) : null}

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

                  <dl className="mt-3 grid grid-cols-2 gap-2 text-sm">
                    {[
                      { ym: lastMonth, report: last },
                      { ym: thisMonth, report: current },
                    ].map(({ ym, report }) => (
                      <div key={ym}>
                        <dt className="mb-1 text-ink-muted">{monthLabelOf(ym)}</dt>
                        <dd>
                          {report ? (
                            <Link href={`/supplier/reports/${report.report_id}`} className="hover:underline">
                              <StatusPill status={report.status} label={report.status_name} />
                            </Link>
                          ) : (
                            <StatusPill status="NONE" label="טרם הוגש" />
                          )}
                        </dd>
                      </div>
                    ))}
                  </dl>
                </li>
              );
            })}
          </ul>
        )}
      </Panel>
    </>
  );
}
