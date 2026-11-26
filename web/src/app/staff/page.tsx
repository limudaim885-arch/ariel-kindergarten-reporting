import Link from "next/link";
import { connection } from "next/server";
import { Callout, PageHead, Panel, buttonClass, secondaryButtonClass } from "@/components/ui";
import { formatMoney, monthLabel, plural } from "@/lib/format";
import { getStaffCaps, getStaffReports } from "@/lib/staff/data";
import { STAGES } from "@/lib/staff/types";

export const metadata = { title: "מסך ראשי - דיווח הגנים" };

export default async function StaffHome() {
  await connection();
  const [{ staff, today, reports }, caps] = await Promise.all([getStaffReports(), getStaffCaps()]);

  const year = Number(today.slice(0, 4));
  const month = Number(today.slice(5, 7));
  const thisMonth = reports.filter((r) => r.year === year && r.month === month);
  const lastMonthKey = month === 1 ? { y: year - 1, m: 12 } : { y: year, m: month - 1 };
  const lastMonth = reports.filter((r) => r.year === lastMonthKey.y && r.month === lastMonthKey.m);
  const blocked = caps.engagements.filter((e) => e.is_blocked).length;
  const warning = caps.engagements.length - blocked;
  const mine = reports.some((r) => r.kindergarten.is_mine);

  const stages = STAGES.map((s) => {
    const list = reports.filter((r) => s.statuses.includes(r.status));
    return { ...s, count: list.length, mine: list.filter((r) => r.kindergarten.is_mine).length };
  });
  const open = stages.filter((s) => s.key !== "final").reduce((sum, s) => sum + s.count, 0);

  return (
    <>
      <PageHead
        title={`שלום, ${staff.full_name}`}
        intro={
          staff.can_act
            ? `${plural(open, "דיווח אחד פתוח", "דיווחים פתוחים")} בתהליך.`
            : `${plural(open, "דיווח אחד פתוח", "דיווחים פתוחים")} בתהליך. ההרשאה שלך היא צפייה בלבד.`
        }
        action={
          stages[1].count ? (
            <Link href="/staff/queue" className={buttonClass}>
              לתור האישורים ({stages[1].count})
            </Link>
          ) : null
        }
      />

      {blocked || warning ? (
        <Callout kind={blocked ? "critical" : "warning"}>
          <p>
            {blocked ? `${plural(blocked, "התקשרות אחת הגיעה", "התקשרויות הגיעו")} לתקרה, והספק לא יכול לדווח עליהן. ` : ""}
            {warning ? `${plural(warning, "התקשרות אחת מתקרבת", "התקשרויות מתקרבות")} לתקרה. ` : ""}
            <Link href="/staff/caps" className="font-semibold underline underline-offset-2">
              לתקרות וחריגות
            </Link>
          </p>
        </Callout>
      ) : null}

      <h2 className="mb-3 text-lg font-semibold text-ink">איפה הדיווחים עומדים</h2>
      <ul className="mb-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {stages.map((s) => (
          <li
            key={s.key}
            className={`flex flex-col rounded-[18px] border p-4 shadow-card ${
              s.key === "queue" && s.count ? "border-accent bg-accent-soft" : "border-line bg-surface"
            }`}
          >
            <h3 className="text-sm font-medium text-ink-muted">{s.label}</h3>
            <p className="mt-1 text-3xl font-semibold tabular-nums text-ink">{s.count}</p>
            <p className="mt-1 text-sm text-ink-muted">
              {s.holder}
              {mine && s.count ? ` · בגנים שלך: ${s.mine}` : ""}
            </p>
            {s.count ? (
              <Link
                href={s.key === "queue" ? "/staff/queue" : `/staff/reports?stage=${s.key}`}
                className={`${secondaryButtonClass} mt-3 self-start`}
                aria-label={`מעבר לרשימה: ${s.label}`}
              >
                מעבר לרשימה
              </Link>
            ) : null}
          </li>
        ))}
      </ul>

      <Panel title="לפי חודש">
        <dl className="grid gap-4 sm:grid-cols-2">
          {[
            { label: monthLabel(year, month), list: thisMonth },
            { label: monthLabel(lastMonthKey.y, lastMonthKey.m), list: lastMonth },
          ].map(({ label, list }) => {
            const locked = list.filter((r) => STAGES[3].statuses.includes(r.status));
            return (
              <div key={label}>
                <dt className="font-semibold text-ink">{label}</dt>
                <dd className="mt-1 text-sm text-ink-muted">
                  {plural(list.length, "דיווח אחד", "דיווחים")}, מתוכם {locked.length} נעולים ·{" "}
                  {formatMoney(locked.reduce((sum, r) => sum + r.amount, 0))} אושרו לתשלום
                </dd>
              </div>
            );
          })}
        </dl>
      </Panel>
    </>
  );
}
