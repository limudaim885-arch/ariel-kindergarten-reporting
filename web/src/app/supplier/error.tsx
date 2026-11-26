"use client";

import { SegmentError } from "@/components/segment-error";

export default function SupplierError({ error, retry }: { error: unknown; retry: () => void }) {
  return <SegmentError area="supplier" error={error} retry={retry} />;
}
