import { connection } from "next/server";
import { PageHead } from "@/components/ui";
import { formatDate } from "@/lib/format";
import { getSupplierData } from "@/lib/supplier/data";
import { ReportForm } from "./report-form";

export const metadata = { title: "דיווח חדש - דיווח הגנים" };

function idParam(value: string | string[] | undefined): number | null {
  const text = Array.isArray(value) ? value[0] : value;
  return text && /^\d{1,9}$/.test(text) ? Number(text) : null;
}

export default async function NewReportPage({ searchParams }: PageProps<"/supplier/new">) {
  await connection();
  const data = await getSupplierData();
  const params = await searchParams;

  return (
    <>
      <PageHead
        title="דיווח חדש"
        intro={`יש לבחור גן, לסמן בלוח את ימי הפעילות ולשלוח. אפשר לסמן ימים בכמה גנים ולשלוח את כולם יחד. אפשר לדווח על תאריכים מ-${formatDate(data.min_date)} ועד היום.`}
      />
      <ReportForm
        engagements={data.engagements}
        reports={data.reports}
        today={data.today}
        minDate={data.min_date}
        holidays={data.holidays}
        initialEngagementId={idParam(params.engagement)}
        fixReportId={idParam(params.report)}
      />
    </>
  );
}
