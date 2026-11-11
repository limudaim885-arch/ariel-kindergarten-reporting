// Opens Supabase Auth users for everyone in access.vw_pending_provisioning.
// A database trigger (trg_link_app_user) then links each new user to the
// teacher, supplier contact or staff record by phone or email.
//
// Usage (from web/):   npm run provision            create the users
//                      npm run provision -- --dry-run   only count
//
// Reads NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from .env.local.
// Prints counts only: never phone numbers, emails or names.
import { createClient } from "@supabase/supabase-js";

type Pending = {
  user_type: "TEACHER" | "SUPPLIER_CONTACT" | "STAFF";
  user_id: number;
  phone: string | null;
  email: string | null;
};

const PAGE_SIZE = 1000;
const dryRun = process.argv.includes("--dry-run");

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) {
  console.error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY (expected in web/.env.local).");
  process.exit(1);
}

const admin = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

async function loadPending(): Promise<Pending[]> {
  const rows: Pending[] = [];
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await admin
      .schema("access")
      .from("vw_pending_provisioning")
      .select("user_type, user_id, phone, email")
      .order("user_type")
      .order("user_id")
      .range(from, from + PAGE_SIZE - 1);
    if (error) throw new Error(`Reading vw_pending_provisioning failed: ${error.message}`);
    rows.push(...(data as Pending[]));
    if (data.length < PAGE_SIZE) return rows;
  }
}

const ALREADY_EXISTS = new Set(["phone_exists", "email_exists", "user_already_exists"]);

async function main() {
  console.log(`Project: ${new URL(url!).hostname}${dryRun ? " (dry run)" : ""}`);

  const pending = await loadPending();
  const byType = (t: Pending["user_type"]) => pending.filter((p) => p.user_type === t).length;
  console.log(
    `Pending records: ${pending.length} (teachers ${byType("TEACHER")}, supplier contacts ${byType("SUPPLIER_CONTACT")}, staff ${byType("STAFF")})`,
  );

  // One auth user per phone or email. The trigger links every record that
  // shares it, so the same number appearing twice is created only once.
  const phones = new Set<string>();
  const emails = new Set<string>();
  let skipped = 0;
  for (const p of pending) {
    if (p.phone) phones.add(p.phone);
    else if (p.email) emails.add(p.email.toLowerCase());
    else skipped++;
  }
  console.log(`To create: ${phones.size} by phone, ${emails.size} by email. No valid phone or email: ${skipped}`);
  if (dryRun) return;

  let created = 0;
  let existing = 0;
  const failures = new Map<string, number>();

  async function create(attributes: Parameters<typeof admin.auth.admin.createUser>[0]) {
    const { error } = await admin.auth.admin.createUser(attributes);
    if (!error) {
      created++;
    } else if (error.code && ALREADY_EXISTS.has(error.code)) {
      existing++;
    } else {
      const reason = error.code ?? `status_${error.status ?? "unknown"}`;
      failures.set(reason, (failures.get(reason) ?? 0) + 1);
    }
  }

  // No password in either case: sign-in is by one-time code only.
  for (const phone of phones) await create({ phone, phone_confirm: true });
  for (const email of emails) await create({ email, email_confirm: true });

  const failed = [...failures.values()].reduce((a, b) => a + b, 0);
  console.log(`Created: ${created}. Already existed: ${existing}. Failed: ${failed}.`);
  for (const [reason, count] of failures) console.log(`  failure ${reason}: ${count}`);

  const remaining = await loadPending();
  console.log(`Still pending after run: ${remaining.length}`);
  if (failed > 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : "Unknown error");
  process.exit(1);
});
