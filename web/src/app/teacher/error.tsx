"use client";

import { SegmentError } from "@/components/segment-error";

export default function TeacherError({ error, retry }: { error: unknown; retry: () => void }) {
  return <SegmentError area="teacher" error={error} retry={retry} />;
}
