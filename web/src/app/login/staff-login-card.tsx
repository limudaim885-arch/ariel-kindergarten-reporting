import { STAFF_LOGIN_MESSAGES, type StaffLoginError } from "@/lib/auth/staff-sso";
import { Card, Message } from "./ui";

// Staff sign in with their Ariel work account (Microsoft). A plain link, not a
// form: the browser navigates to /auth/microsoft, which sends it on to Microsoft.
export function StaffLoginCard({ error }: { error: StaffLoginError | null }) {
  return (
    <Card title="כניסת צוות החברה העירונית">
      <p className="mb-3 text-center text-ink-muted">
        כניסה עם חשבון העבודה של אריאל (Microsoft). אין צורך בקוד או בסיסמה נוספת.
      </p>
      {error && (
        <Message kind="error" id="staff-msg">
          {STAFF_LOGIN_MESSAGES[error]}
        </Message>
      )}
      <div className="flex-1" />
      <a
        href="/auth/microsoft"
        aria-describedby={error ? "staff-msg" : undefined}
        className="block w-full rounded-[10px] bg-accent px-4 py-3 text-center text-base font-semibold text-on-fill hover:bg-accent-strong"
      >
        כניסה עם חשבון אריאל
      </a>
    </Card>
  );
}
