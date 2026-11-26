import Link from "next/link";
import { connection } from "next/server";
import { Callout, PageHead, Panel, buttonClass } from "@/components/ui";
import { formatDateTime, formatMoney, monthLabel, plural } from "@/lib/format";
import { getTeacherData } from "@/lib/teacher/data";
import { isPending } from "@/lib/teacher/types";

export const metadata = { title: "תיבת אישורים - דיווח הגנים" };

const DONE: Record<string, string> = {
  approved: "הדיווח אושר ונשלח לבדיקת הרפרנטית. אין צורך לעשות דבר נוסף.",
  returned: "הדיווח הוחזר לספק לתיקון, יחד עם ההערה שלך.",
};

export default async function TeacherInbox({ searchParams }: PageProps<"/teacher">) {
  await connection();
  const data = await getTeacherData();
  const done = (await searchParams).done;
  const doneText = typeof done === "string" ? DONE[done] : undefined;

  const pending = data.reports
    .filter(isPending)
    .sort((a, b) => (a.submitted_at ?? "").localeCompare(b.submitted_at ?? ""));
  const manualGardens = data.kindergartens.filter((k) => k.is_manual_track);
  const severalGardens = data.kindergartens.length > 1;

  return (
    <>
      <PageHead
        title={`שלום, ${data.teacher.full_name}`}
        intro={
          data.kindergartens.length
            ? `${data.kindergartens.map((k) => `${k.name} (${k.code})`).join(" · ")}`
            : "אין לך כרגע שיבוץ פעיל בגן. יש לפנות לרפרנטית."
        }
      />

      {doneText ? (
        <Callout kind="success" role="status">
          <p>
            <strong>{doneText}</strong>
          </p>
        </Callout>
      ) : null}

      {manualGardens.map((k) => (
        <Callout key={k.kindergarten_id} kind="info">
          <p>
            {k.name} במסלול טופס ידני. את הדיווחים של הגן הזה ממשיכים לחתום בטופס הנייר, והרפרנטית מזינה אותם.
          </p>
        </Callout>
      ))}

      <Panel title={pending.length ? `ממתינים לאישור שלך (${pending.length})` : "ממתינים לאישור שלך"}>
        {pending.length === 0 ? (
          <p className="text-ink-muted">אין דיווחים שממתינים לאישורך כרגע. כשספק ישלח דיווח, הוא יופיע כאן.</p>
        ) : (
          <ul className="space-y-3">
            {pending.map((r) => (
              <li
                key={r.report_id}
                className="flex flex-wrap items-center justify-between gap-3 rounded-[14px] border border-line p-4"
              >
                <div>
                  <h3 className="font-semibold text-ink">
                    {r.supplier.name} · {monthLabel(r.year, r.month)}
                  </h3>
                  <p className="text-sm text-ink-muted">
                    {r.domain}
                    {severalGardens ? ` · ${r.kindergarten.name}` : ""} · {plural(r.sessions, "מפגש אחד", "מפגשים")} ·{" "}
                    {formatMoney(r.amount)}
                    {r.submitted_at ? ` · נשלח ${formatDateTime(r.submitted_at)}` : ""}
                  </p>
                </div>
                <Link
                  href={`/teacher/reports/${r.report_id}`}
                  className={buttonClass}
                  aria-label={`בדיקה ואישור: ${r.supplier.name}, ${monthLabel(r.year, r.month)}`}
                >
                  בדיקה ואישור
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Panel>

      <p className="text-sm text-ink-muted">
        דיווחים שכבר אישרת או החזרת נמצאים ב
        <Link href="/teacher/history" className="font-medium text-accent underline underline-offset-2">
          דיווחים שטופלו
        </Link>
        .
      </p>
    </>
  );
}
