export type PhoneUserType = "SUPPLIER_CONTACT" | "TEACHER";

export type PhoneOption = { id: number; masked: string };

export type ActionResult<T = object> =
  | ({ ok: true } & T)
  | { ok: false; message: string; exhausted?: boolean };
