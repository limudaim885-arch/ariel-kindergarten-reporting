"use client";

import { SegmentError } from "@/components/segment-error";

export default function StaffError({ error, retry }: { error: unknown; retry: () => void }) {
  return <SegmentError area="staff" error={error} retry={retry} />;
}
