import "server-only";
import { connection } from "next/server";
import { allow } from "@/lib/rate-limit";
import { createAdminClient } from "@/lib/supabase/admin";

// Target of the uptime check (.github/workflows/uptime.yml).
// Answers 200 only when the app is up and the database answers through
// access.health_check() (migration 12). It returns no data and no error
// details; the reason for a failure goes to the server log only.
const DB_TIMEOUT_MS = 5_000;

function reply(status: "ok" | "error" | "busy", httpStatus: number) {
  return Response.json(
    { status },
    { status: httpStatus, headers: { "Cache-Control": "no-store" } },
  );
}

export async function GET() {
  await connection();

  if (!(await allow("health"))) return reply("busy", 429);

  try {
    const { data, error } = await createAdminClient()
      .schema("access")
      .rpc("health_check")
      .abortSignal(AbortSignal.timeout(DB_TIMEOUT_MS));

    if (error) {
      console.error("health: database check failed:", error.message);
      return reply("error", 503);
    }
    if (data !== true) {
      console.error("health: database check returned an unexpected value");
      return reply("error", 503);
    }
    return reply("ok", 200);
  } catch (e) {
    console.error("health: database check threw:", e instanceof Error ? e.message : "unknown error");
    return reply("error", 503);
  }
}
