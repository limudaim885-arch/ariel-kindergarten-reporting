/* =====================================================================
   10_lockout_policy.sql  |  PostgreSQL (Supabase)
   מדיניות נעילה חדשה (לפי ה-PR "Security hardening: OWASP Top 10:2025", סעיף A06)
   ---------------------------------------------------------------------
   הגנה מפני ניחוש קודים, בלי לנעול משתמש לגיטימי שטעה:
   1. כל קוד נפסל אחרי OtpMaxAttempts (3) ניסיונות שגויים. צריך לבקש קוד חדש.
   2. הטלפון ננעל רק אחרי OtpPhoneLockThreshold (10) כישלונות בתוך
      OtpPhoneLockWindowMinutes (60), למשך OtpLockMinutes (15).
   3. רפרנטית יכולה לשחרר נעילה, והשחרור נרשם ביומן הפעולות.

   תהליך בשרת:
     שליחת קוד:  can_send_otp ← signInWithOtp ← register_otp_sent
     בדיקת קוד:  verify_status ('OK' בלבד ממשיכים) ← verifyOtp
                 שגוי ← register_failed_attempt   |   נכון ← reset_failed_attempts
   כל הפונקציות מקבלות טלפון בכל פורמט (0501234567 / 972501234567 / +972501234567).
   להריץ אחרי 07 ו-09. אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

/* ---------- טבלת הנעילות ---------- */
ALTER TABLE access.phone_lockouts ADD COLUMN IF NOT EXISTS code_failed_attempts smallint NOT NULL DEFAULT 0;  -- טעויות בקוד הנוכחי
ALTER TABLE access.phone_lockouts ADD COLUMN IF NOT EXISTS window_started_at   timestamptz(0) NULL;            -- תחילת חלון הספירה
ALTER TABLE access.phone_lockouts ADD COLUMN IF NOT EXISTS lock_count          smallint NOT NULL DEFAULT 0;  -- כמה פעמים ננעל (סימן לניסיון תקיפה)
ALTER TABLE access.phone_lockouts ADD COLUMN IF NOT EXISTS unlocked_by_staff_user_id integer NULL
    REFERENCES core.staff_users (staff_user_id);
ALTER TABLE access.phone_lockouts ADD COLUMN IF NOT EXISTS unlocked_at         timestamptz(0) NULL;
COMMENT ON COLUMN access.phone_lockouts.failed_attempts IS 'כישלונות בחלון הנוכחי';

/* ---------- הגדרות ---------- */
UPDATE ref.settings SET description_he = 'ניסיונות שגויים לקוד בודד עד פסילתו (נדרש קוד חדש)' WHERE setting_key = 'OtpMaxAttempts';
UPDATE ref.settings SET setting_value = '15', description_he = 'משך נעילת נייד בדקות. רפרנטית יכולה לשחרר מוקדם' WHERE setting_key = 'OtpLockMinutes';
INSERT INTO ref.settings (setting_key, setting_value, value_type, description_he) VALUES
 ('OtpPhoneLockThreshold',     '10', 'INT', 'כישלונות לנייד בתוך החלון עד נעילת הנייד'),
 ('OtpPhoneLockWindowMinutes', '60', 'INT', 'חלון הזמן לספירת כישלונות לנייד, בדקות')
ON CONFLICT (setting_key) DO NOTHING;

/* ---------- פונקציות ---------- */

-- נשלח קוד חדש: רישום ביומן ההודעות ואיפוס מונה הטעויות של הקוד
CREATE OR REPLACE FUNCTION access.register_otp_sent(p_phone text, p_recipient_type text, p_recipient_id int)
RETURNS bigint
LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
    v_ph text := access.to_local(p_phone);
    v_id bigint;
BEGIN
    IF v_ph IS NULL THEN
        RAISE EXCEPTION 'מספר טלפון לא תקין';
    END IF;
    INSERT INTO ops.notifications (channel, purpose, recipient_type, recipient_id, destination, status, sent_at)
    VALUES ('SMS', 'OTP', p_recipient_type, p_recipient_id, v_ph, 'SENT', now())
    RETURNING notification_id INTO v_id;

    UPDATE access.phone_lockouts SET code_failed_attempts = 0 WHERE mobile_phone = v_ph;
    RETURN v_id;
END $$;

-- לפני verifyOtp: OK / LOCKED (הנייד נעול) / CODE_EXHAUSTED (הקוד נפסל, צריך קוד חדש)
CREATE OR REPLACE FUNCTION access.verify_status(p_phone text) RETURNS text
LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT CASE
        WHEN access.phone_locked_until(p_phone) IS NOT NULL THEN 'LOCKED'
        WHEN coalesce((SELECT code_failed_attempts FROM access.phone_lockouts
                        WHERE mobile_phone = access.to_local(p_phone)), 0)
             >= ref.setting_int('OtpMaxAttempts', 3) THEN 'CODE_EXHAUSTED'
        ELSE 'OK'
    END
$$;

-- קוד שגוי. מחזיר: { "code_exhausted": bool, "locked_until": timestamp | null }
DROP FUNCTION IF EXISTS access.register_failed_attempt(text);
CREATE FUNCTION access.register_failed_attempt(p_phone text) RETURNS jsonb
LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
    v_ph        text := access.to_local(p_phone);
    v_code_max  int  := ref.setting_int('OtpMaxAttempts', 3);
    v_threshold int  := ref.setting_int('OtpPhoneLockThreshold', 10);
    v_window    int  := ref.setting_int('OtpPhoneLockWindowMinutes', 60);
    v_lock      int  := ref.setting_int('OtpLockMinutes', 15);
    v_row       access.phone_lockouts;
BEGIN
    IF v_ph IS NULL THEN
        RAISE EXCEPTION 'מספר טלפון לא תקין';
    END IF;

    INSERT INTO access.phone_lockouts AS p (mobile_phone, failed_attempts, code_failed_attempts, window_started_at, last_failed_at)
    VALUES (v_ph, 1, 1, now(), now())
    ON CONFLICT (mobile_phone) DO UPDATE SET
        -- חלון חדש אם הקודם פג
        failed_attempts      = CASE WHEN p.window_started_at IS NULL
                                      OR p.window_started_at <= now() - make_interval(mins => v_window)
                                    THEN 1 ELSE p.failed_attempts + 1 END,
        window_started_at    = CASE WHEN p.window_started_at IS NULL
                                      OR p.window_started_at <= now() - make_interval(mins => v_window)
                                    THEN now() ELSE p.window_started_at END,
        code_failed_attempts = p.code_failed_attempts + 1,
        last_failed_at       = now()
    RETURNING * INTO v_row;

    IF v_row.failed_attempts >= v_threshold
       AND (v_row.locked_until IS NULL OR v_row.locked_until <= now()) THEN
        UPDATE access.phone_lockouts
           SET locked_until      = now() + make_interval(mins => v_lock),
               lock_count        = lock_count + 1,
               failed_attempts   = 0,
               window_started_at = NULL
         WHERE mobile_phone = v_ph
        RETURNING * INTO v_row;
    END IF;

    RETURN jsonb_build_object(
        'code_exhausted', v_row.code_failed_attempts >= v_code_max,
        'locked_until',   CASE WHEN v_row.locked_until > now() THEN v_row.locked_until END);
END $$;

-- כניסה מוצלחת: איפוס המונים (ההיסטוריה של lock_count נשמרת)
CREATE OR REPLACE FUNCTION access.reset_failed_attempts(p_phone text) RETURNS void
LANGUAGE sql SET search_path = '' AS $$
    UPDATE access.phone_lockouts
       SET failed_attempts = 0, code_failed_attempts = 0, window_started_at = NULL
     WHERE mobile_phone = access.to_local(p_phone)
$$;

-- שחרור נעילה על ידי רפרנטית או מנהלת. נרשם ביומן הפעולות. מחזיר true אם הנייד היה נעול
CREATE OR REPLACE FUNCTION access.unlock_phone(p_phone text, p_staff_user_id int) RETURNS boolean
LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
    v_ph   text := access.to_local(p_phone);
    v_was  boolean;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.staff_users s JOIN ref.staff_roles r ON r.role_id = s.role_id
                   WHERE s.staff_user_id = p_staff_user_id AND s.is_active AND r.code IN ('ADMIN','REFERENT')) THEN
        RAISE EXCEPTION 'אין הרשאה לשחרר נעילה';
    END IF;

    UPDATE access.phone_lockouts
       SET locked_until = NULL, failed_attempts = 0, code_failed_attempts = 0, window_started_at = NULL,
           unlocked_by_staff_user_id = p_staff_user_id, unlocked_at = now()
     WHERE mobile_phone = v_ph
    RETURNING true INTO v_was;

    INSERT INTO audit.action_log (actor_type, actor_id, action, entity_name, details)
    VALUES ('STAFF', p_staff_user_id, 'PHONE_UNLOCK', 'phone',
            jsonb_build_object('phone', left(v_ph,3) || '-***' || right(v_ph,4)));
    RETURN coalesce(v_was, false);
END $$;

-- למסך הרפרנטית: נייד נעול עכשיו, או שננעל יותר מפעם אחת (סימן לניסיון תקיפה)
CREATE OR REPLACE VIEW access.vw_phone_lockouts WITH (security_invoker = true) AS
SELECT  p.mobile_phone,
        left(p.mobile_phone,3) || '-***' || right(p.mobile_phone,4) AS masked_phone,
        coalesce(t.full_name, c.full_name)                         AS full_name,
        CASE WHEN t.teacher_id IS NOT NULL THEN 'TEACHER'
             WHEN c.contact_id IS NOT NULL THEN 'SUPPLIER_CONTACT' END AS user_type,
        p.locked_until > now()                                      AS is_locked,
        p.locked_until,
        p.lock_count,
        p.last_failed_at,
        p.unlocked_at
FROM    access.phone_lockouts p
LEFT JOIN core.teachers t          ON t.mobile_phone = p.mobile_phone AND t.is_active
LEFT JOIN core.supplier_contacts c ON c.mobile_phone = p.mobile_phone AND c.is_active
WHERE   p.locked_until > now() OR p.lock_count > 1;

/* ---------- הרשאות ---------- */
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA access FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON ALL TABLES    IN SCHEMA access FROM anon, authenticated;
        REVOKE ALL ON ALL FUNCTIONS IN SCHEMA access FROM anon, authenticated;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        GRANT ALL ON ALL TABLES IN SCHEMA access TO service_role;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA access TO service_role;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
        GRANT EXECUTE ON FUNCTION access.tg_link_auth_user() TO supabase_auth_admin;
        GRANT EXECUTE ON FUNCTION access.send_sms_hook(jsonb) TO supabase_auth_admin;
    END IF;
END $$;

COMMIT;

SELECT '10_lockout_policy.sql הושלם' AS status;
