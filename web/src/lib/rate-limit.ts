import "server-only";
import { headers } from "next/headers";

// Simple sliding-window limiter kept in memory. On Vercel each server
// instance has its own counters, so this is a basic brake against scripted
// abuse, not a hard guarantee. Move it to a table if stricter limits are needed.
const hits = new Map<string, number[]>();
const MAX_KEYS = 10_000;

export type RateRule = { max: number; windowMs: number };

export const RULES = {
  lookupOptions: { max: 10, windowMs: 60_000 },
  sendCode: { max: 5, windowMs: 10 * 60_000 },
  verifyCode: { max: 15, windowMs: 10 * 60_000 },
  staffSend: { max: 5, windowMs: 10 * 60_000 },
  staffVerify: { max: 15, windowMs: 10 * 60_000 },
} satisfies Record<string, RateRule>;

export async function clientIp(): Promise<string> {
  const h = await headers();
  const forwarded = h.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || h.get("x-real-ip") || "unknown";
}

/** Returns true if the request is allowed, and records it. */
export async function allow(action: keyof typeof RULES): Promise<boolean> {
  const rule = RULES[action];
  const key = `${action}:${await clientIp()}`;
  const now = Date.now();
  const recent = (hits.get(key) ?? []).filter((t) => now - t < rule.windowMs);

  if (recent.length >= rule.max) {
    hits.set(key, recent);
    return false;
  }
  recent.push(now);
  hits.set(key, recent);

  if (hits.size > MAX_KEYS) {
    for (const [k, times] of hits) {
      if (times.every((t) => now - t >= 10 * 60_000)) hits.delete(k);
    }
  }
  return true;
}
