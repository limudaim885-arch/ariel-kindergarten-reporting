"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { staffSendCode, staffVerifyCode } from "./actions";
import { Card, Field, LinkButton, Message, PrimaryButton, inputClass, otpInputClass } from "./ui";

export function StaffLoginCard() {
  const [step, setStep] = useState<"email" | "code">("email");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const focusRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    focusRef.current?.focus();
  }, [step]);

  function onSend(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const result = await staffSendCode(email);
      if (!result.ok) return setError(result.message);
      setCode("");
      setStep("code");
    });
  }

  function onVerify(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const result = await staffVerifyCode(email, code);
      if (result && !result.ok) {
        setError(result.message);
        setCode("");
      }
    });
  }

  function back() {
    setStep("email");
    setCode("");
    setError(null);
  }

  return (
    <Card title="כניסת צוות החברה העירונית">
      {step === "email" ? (
        <form onSubmit={onSend} className="flex flex-1 flex-col" noValidate>
          <p className="mb-3 text-center text-ink-muted">
            כתובת המייל של הצוות, ולאחריה קוד חד-פעמי שיישלח אליה.
          </p>
          {error && <Message kind="error" id="staff-msg">{error}</Message>}
          <Field id="staff-email" label="כתובת מייל">
            <input
              ref={focusRef}
              id="staff-email"
              type="email"
              autoComplete="username"
              maxLength={254}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              aria-describedby={error ? "staff-msg" : undefined}
              aria-invalid={error ? true : undefined}
              dir="ltr"
              className={inputClass}
            />
          </Field>
          <div className="flex-1" />
          <PrimaryButton disabled={pending || email.trim().length === 0}>שליחת קוד</PrimaryButton>
        </form>
      ) : (
        <form onSubmit={onVerify} className="flex flex-1 flex-col" noValidate>
          <p className="mb-3 text-center text-ink-muted">
            אם הכתובת רשומה במערכת, נשלח אליה קוד בן 6 ספרות.
          </p>
          {error && <Message kind="error" id="staff-msg">{error}</Message>}
          <Field id="staff-code" label="קוד אימות">
            <input
              ref={focusRef}
              id="staff-code"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              aria-describedby={error ? "staff-msg" : undefined}
              aria-invalid={error ? true : undefined}
              className={otpInputClass}
            />
          </Field>
          <div className="flex-1" />
          <PrimaryButton disabled={pending || code.length !== 6}>אימות וכניסה</PrimaryButton>
          <div className="mt-3 flex justify-end">
            <LinkButton onClick={back}>חזרה</LinkButton>
          </div>
        </form>
      )}
    </Card>
  );
}
