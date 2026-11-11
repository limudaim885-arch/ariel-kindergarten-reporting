"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { lookupOptions, sendCode, verifyCode } from "./actions";
import type { PhoneOption, PhoneUserType } from "./types";
import { Card, Field, LinkButton, Message, PrimaryButton, inputClass, otpInputClass } from "./ui";

type Step = "id" | "pick" | "code";

const RESEND_SECONDS = 30;

export function PhoneLoginCard({
  userType,
  title,
  intro,
  keyLabel,
  idPrefix,
}: {
  userType: PhoneUserType;
  title: string;
  intro: string;
  keyLabel: string;
  idPrefix: string;
}) {
  const [step, setStep] = useState<Step>("id");
  const [loginKey, setLoginKey] = useState("");
  const [options, setOptions] = useState<PhoneOption[]>([]);
  const [optionId, setOptionId] = useState<number | null>(null);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [exhausted, setExhausted] = useState(false);
  const [secondsLeft, setSecondsLeft] = useState(0);
  const [pending, startTransition] = useTransition();
  const focusRef = useRef<HTMLInputElement>(null);

  const keyId = `${idPrefix}-key`;
  const codeId = `${idPrefix}-code`;
  const msgId = `${idPrefix}-msg`;
  const chosen = options.find((o) => o.id === optionId);

  useEffect(() => {
    focusRef.current?.focus();
  }, [step]);

  useEffect(() => {
    if (secondsLeft <= 0) return;
    const timer = setTimeout(() => setSecondsLeft((s) => s - 1), 1000);
    return () => clearTimeout(timer);
  }, [secondsLeft]);

  function fail(message: string, wasExhausted = false) {
    setError(message);
    setInfo(null);
    setExhausted(wasExhausted);
  }

  function back() {
    setStep("id");
    setOptions([]);
    setOptionId(null);
    setCode("");
    setError(null);
    setInfo(null);
    setExhausted(false);
  }

  function send(id: number) {
    startTransition(async () => {
      const result = await sendCode({ userType, loginKey, optionId: id });
      if (!result.ok) return fail(result.message);
      setOptionId(id);
      setCode("");
      setError(null);
      setExhausted(false);
      setInfo("קוד אימות נשלח בהודעת SMS.");
      setSecondsLeft(RESEND_SECONDS);
      setStep("code");
    });
  }

  function onLookup(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const result = await lookupOptions(userType, loginKey);
      if (!result.ok) return fail(result.message);
      setOptions(result.options);
      setOptionId(result.options[0].id);
      setStep("pick");
    });
  }

  function onPick(e: React.FormEvent) {
    e.preventDefault();
    if (optionId !== null) send(optionId);
  }

  function onVerify(e: React.FormEvent) {
    e.preventDefault();
    if (optionId === null) return;
    setError(null);
    startTransition(async () => {
      // On success the action redirects; a returned value is always a failure.
      const result = await verifyCode({ userType, loginKey, optionId, code });
      if (result && !result.ok) {
        fail(result.message, result.exhausted);
        setCode("");
      }
    });
  }

  return (
    <Card title={title}>
      {step === "id" && (
        <form onSubmit={onLookup} className="flex flex-1 flex-col" noValidate>
          <p className="mb-3 text-center text-ink-muted">{intro}</p>
          {error && <Message kind="error" id={msgId}>{error}</Message>}
          <Field id={keyId} label={keyLabel}>
            <input
              ref={focusRef}
              id={keyId}
              type="text"
              inputMode="numeric"
              autoComplete="username"
              maxLength={10}
              value={loginKey}
              onChange={(e) => setLoginKey(e.target.value.replace(/\D/g, ""))}
              aria-describedby={error ? msgId : undefined}
              aria-invalid={error ? true : undefined}
              className={inputClass}
            />
          </Field>
          <div className="flex-1" />
          <PrimaryButton disabled={pending || loginKey.length === 0}>המשך</PrimaryButton>
        </form>
      )}

      {step === "pick" && (
        <form onSubmit={onPick} className="flex flex-1 flex-col">
          <p className="mb-3 text-center text-ink-muted">
            {options.length > 1
              ? "יש לבחור את הנייד שלך. הקוד יישלח רק אליו."
              : "הקוד יישלח לנייד הרשום."}
          </p>
          {error && <Message kind="error" id={msgId}>{error}</Message>}
          <fieldset className="mb-3 rounded-[10px] border border-line p-3">
            <legend className="px-1 text-sm font-medium text-ink">הנייד שלך</legend>
            {options.map((o, i) => (
              <label key={o.id} className="flex cursor-pointer items-center gap-2 py-1.5">
                <input
                  ref={i === 0 ? focusRef : undefined}
                  type="radio"
                  name={`${idPrefix}-phone`}
                  value={o.id}
                  checked={optionId === o.id}
                  onChange={() => setOptionId(o.id)}
                  className="size-4 accent-[var(--accent)]"
                />
                <span dir="ltr" className="tabular-nums">{o.masked}</span>
              </label>
            ))}
          </fieldset>
          <div className="flex-1" />
          <PrimaryButton disabled={pending || optionId === null}>שליחת קוד ב-SMS</PrimaryButton>
          <div className="mt-3 flex justify-end">
            <LinkButton onClick={back}>חזרה</LinkButton>
          </div>
        </form>
      )}

      {step === "code" && (
        <form onSubmit={onVerify} className="flex flex-1 flex-col" noValidate>
          <p className="mb-3 text-center text-ink-muted">
            הקוד נשלח לנייד <span dir="ltr" className="tabular-nums">{chosen?.masked}</span>.
            יש להזין את 6 הספרות שהתקבלו.
          </p>
          {info && !error && <Message kind="info" id={msgId}>{info}</Message>}
          {error && <Message kind="error" id={msgId}>{error}</Message>}
          <Field id={codeId} label="קוד אימות">
            <input
              ref={focusRef}
              id={codeId}
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              aria-describedby={error ? msgId : undefined}
              aria-invalid={error ? true : undefined}
              disabled={exhausted}
              className={otpInputClass}
            />
          </Field>
          <div className="flex-1" />
          <PrimaryButton disabled={pending || exhausted || code.length !== 6}>אימות וכניסה</PrimaryButton>
          <div className="mt-3 flex items-center justify-between gap-2">
            <LinkButton
              onClick={() => optionId !== null && send(optionId)}
              disabled={pending || secondsLeft > 0}
            >
              שליחת קוד חדש
            </LinkButton>
            <span className="text-sm text-ink-muted" aria-live="off">
              {secondsLeft > 0 ? `אפשר לבקש קוד חדש בעוד ${secondsLeft} שניות` : ""}
            </span>
            <LinkButton onClick={back}>חזרה</LinkButton>
          </div>
        </form>
      )}
    </Card>
  );
}
