import type { Metadata } from "next";
import { Heebo } from "next/font/google";
import { connection } from "next/server";
import "./globals.css";

const heebo = Heebo({
  variable: "--font-heebo",
  subsets: ["hebrew", "latin"],
});

export const metadata: Metadata = {
  title: "דיווח הגנים - חברה עירונית אריאל",
  description: "מערכת דיווח ואישור דיגיטליים של פעילות ספקים בגני ילדים",
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
  // The CSP nonce is per request, so pages must not be prerendered.
  await connection();
  return (
    <html lang="he" dir="rtl" className={`${heebo.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
