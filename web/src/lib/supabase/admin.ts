import "server-only";
import { createClient } from "@supabase/supabase-js";
import { env } from "@/lib/env";

// Actor format: '<TYPE>:<ID>', e.g. 'STAFF:12'. The database reads the
// x-app-actor header (migration 09) to record who made the change.
const ACTOR_PATTERN = /^[A-Z_]+:\d+$/;

/**
 * Server-only client that uses the service_role key and bypasses RLS.
 * Never import this from code that runs in the browser.
 * Pass `actor` on every request that changes data.
 */
export function createAdminClient(actor?: string) {
  if (actor !== undefined && !ACTOR_PATTERN.test(actor)) {
    throw new Error("Invalid actor");
  }
  return createClient(env.supabaseUrl, env.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: actor ? { headers: { "x-app-actor": actor } } : undefined,
  });
}
