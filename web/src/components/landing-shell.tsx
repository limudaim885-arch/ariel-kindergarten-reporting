import { signOut } from "@/lib/auth/actions";
import type { AppUser } from "@/lib/auth/access";

// Temporary landing page for each role until the real screens are built.
export function LandingShell({ user, heading }: { user: AppUser; heading: string }) {
  return (
    <main className="mx-auto w-full max-w-3xl flex-1 px-4 py-10">
      <h1 className="mb-2 text-2xl font-semibold">{heading}</h1>
      <p className="mb-6 text-ink-muted">
        שלום {user.full_name}. המסכים של התפקיד הזה עדיין בבנייה.
      </p>
      <form action={signOut}>
        <button
          type="submit"
          className="rounded-[10px] border border-line-strong bg-surface px-4 py-2 font-medium text-ink"
        >
          יציאה
        </button>
      </form>
    </main>
  );
}
