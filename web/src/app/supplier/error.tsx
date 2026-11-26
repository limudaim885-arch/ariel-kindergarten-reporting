"use client";

import { useEffect } from "react";

export default function SupplierError({ error, retry }: { error: unknown; retry: () => void }) {
  useEffect(() => {
    console.error("[supplier]", error instanceof Error ? error.message : "unknown error");
  }, [error]);

  return (
    <div role="alert" className="rounded-[18px] border border-line bg-surface p-6 text-center shadow-card">
      <h1 className="mb-2 text-xl font-semibold text-ink">לא הצלחנו לטעון את הנתונים</h1>
      <p className="mb-4 text-ink-muted">יש לנסות שוב בעוד רגע. אם זה חוזר, יש לפנות לרפרנטית.</p>
      <button
        type="button"
        onClick={() => retry()}
        className="rounded-[10px] bg-accent px-4 py-2.5 font-semibold text-on-fill hover:bg-accent-strong"
      >
        ניסיון נוסף
      </button>
    </div>
  );
}
