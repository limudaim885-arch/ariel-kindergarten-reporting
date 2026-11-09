import { redirect } from "next/navigation";
import { connection } from "next/server";
import { getAppUser, HOME_BY_TYPE } from "@/lib/auth/session";
import { PhoneLoginCard } from "./phone-login-card";
import { StaffLoginCard } from "./staff-login-card";

export const metadata = { title: "כניסה - דיווח הגנים" };

export default async function LoginPage() {
  await connection();

  let home: string | null = null;
  try {
    const user = await getAppUser();
    if (user) home = HOME_BY_TYPE[user.user_type];
  } catch (err) {
    // Keep the login page available if the session check fails.
    console.error("[login] session check:", err instanceof Error ? err.message : "unknown error");
  }
  if (home) redirect(home);

  return (
    <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8 sm:px-6">
      <div className="mx-auto mb-6 max-w-2xl text-center">
        {/* Plain img: next/image adds an inline style that the CSP blocks. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src="/ariel-logo.png"
          alt="החברה העירונית אריאל"
          width={200}
          height={63}
          className="mx-auto mb-4 rounded-xl bg-white p-2"
        />
        <h1 className="mb-2 text-3xl font-semibold">דיווח הגנים</h1>
        <p className="text-ink-muted">
          דיווח, חתימה ואישור דיגיטליים לפעילות של ספקים חיצוניים בגני הילדים של החברה העירונית אריאל.
        </p>
      </div>

      <p className="mx-auto mb-6 max-w-2xl rounded-xl bg-info-soft px-4 py-3 text-info">
        <strong>איך להתחבר:</strong> כל משתמש נכנס דרך הכרטיס המתאים לו. ספקים נכנסים עם מספר ספק, וגננות
        עם סמל הגן. כל אחד בוחר את הנייד שלו מתוך הרשימה, ומקבל קוד חד-פעמי ב-SMS.
      </p>

      <div className="grid gap-4 md:grid-cols-3">
        <PhoneLoginCard
          userType="SUPPLIER_CONTACT"
          title="כניסת ספקים"
          intro="מספר הספק שלך, ולאחר מכן קוד חד-פעמי לנייד הרשום. אין צורך בשם משתמש או בסיסמה."
          keyLabel="מספר ספק"
          idPrefix="supplier"
        />
        <StaffLoginCard />
        <PhoneLoginCard
          userType="TEACHER"
          title="כניסת גננות"
          intro="סמל הגן, ולאחר מכן קוד חד-פעמי לנייד שלך ב-SMS."
          keyLabel="סמל גן"
          idPrefix="teacher"
        />
      </div>
    </main>
  );
}
