import Link from "next/link";

export const metadata = { title: "הדף לא נמצא - דיווח הגנים" };

// Next's built-in 404 page uses inline styles, which our CSP blocks.
export default function NotFound() {
  return (
    <main id="main" className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center px-4 py-10">
      <div className="rounded-[18px] border border-line bg-surface p-6 text-center shadow-card">
        <h1 className="mb-2 text-xl font-semibold text-ink">הדף לא נמצא</h1>
        <p className="mb-4 text-ink-muted">ייתכן שהקישור שגוי, או שאין לך הרשאה לצפות בדף הזה.</p>
        <Link
          href="/login"
          className="inline-block rounded-[10px] bg-accent px-4 py-2.5 font-semibold text-on-fill hover:bg-accent-strong"
        >
          חזרה לדף הבית
        </Link>
      </div>
    </main>
  );
}
