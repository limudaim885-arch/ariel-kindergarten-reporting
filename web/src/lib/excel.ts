import "server-only";
import writeExcelFile, { type Cell, type Row, type Sheet } from "write-excel-file/node";

// Excel downloads for staff. Every sheet is right-to-left with a frozen,
// bold header row. Text cells are written as text, so a value that starts
// with "=" never becomes a formula.

type ExcelSheet = { name: string; header: string[]; rows: Row[]; widths: number[]; totals?: Row };

export const MONEY = "#,##0.00";

export function money(value: number): Cell {
  return { value, type: Number, format: MONEY };
}

export function num(value: number): Cell {
  return { value, type: Number };
}

function bold(row: Row): Row {
  return row.map((cell) => {
    if (cell === null || cell === undefined) return cell;
    if (typeof cell === "object" && !(cell instanceof Date) && "value" in cell) return { ...cell, fontWeight: "bold" };
    return { value: cell as string | number, fontWeight: "bold" };
  });
}

export async function xlsxResponse(sheets: ExcelSheet[], fileName: string, asciiName: string): Promise<Response> {
  const data: Sheet<Buffer>[] = sheets.map((s) => ({
    sheet: s.name.slice(0, 31),
    rightToLeft: true,
    stickyRowsCount: 1,
    columns: s.widths.map((width) => ({ width })),
    data: [
      s.header.map((h) => ({ value: h, fontWeight: "bold", backgroundColor: "#E8ECF7" })),
      ...s.rows,
      ...(s.totals ? [bold(s.totals)] : []),
    ],
  }));

  const buffer = await writeExcelFile(data).toBuffer();
  return new Response(new Uint8Array(buffer), {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${asciiName}"; filename*=UTF-8''${encodeURIComponent(fileName)}`,
      "Cache-Control": "no-store",
    },
  });
}
