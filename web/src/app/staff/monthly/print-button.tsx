"use client";

import { secondaryButtonClass } from "@/components/ui";

export function PrintButton() {
  return (
    <button type="button" onClick={() => window.print()} className={`${secondaryButtonClass} print:hidden`}>
      הדפסה
    </button>
  );
}
