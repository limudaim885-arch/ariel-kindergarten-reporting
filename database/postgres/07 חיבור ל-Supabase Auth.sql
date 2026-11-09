/* =====================================================================
   07_supabase_auth.sql  |  שלב א'  |  PostgreSQL (Supabase)
   מעבר לכניסה דרך Supabase Auth
   ---------------------------------------------------------------------
   החלטות (נובמבר 2026):
   * ספקים וגננות: כניסה עם קוד SMS דרך Supabase Auth. השליחה עצמה דרך mgroup
     (Send SMS Hook), שם השולח: Ariel.
   * צוות אריאל (רפרנטיות): כניסה עם קוד אימות למייל בלבד.
   * אין הרשמה עצמית. משתמש נפתח ב-Supabase Auth רק על ידי השרת או הצוות,
     ונקשר אוטומטית לגננת / לאיש הקשר / לאיש הצוות לפי הטלפון או המייל.
   * במסך הכניסה מוצג רק הטלפון המוסתר של המשתמשים ששייכים לספק או לגן
     שהוקלד. מספר מלא לא יוצא מהמסד לדפדפן אף פעם.

   מה הקובץ עושה:
   1. מחזק את טריגר ההיסטוריה (התאמה לפי שם עמודה), כדי שהוספת עמודות לא תשבור אותו.
   2. מוסיף auth_user_id לגננות, לאנשי הקשר ולצוות, וקישור אוטומטי מ-auth.users.
   3. אישור גננת: הראיה היא המשתמש והסשן של Supabase במקום רשומת קוד שלנו.
   4. מוחק את access.otp_requests (Supabase מנהל את הקודים). נעילת טלפון אחרי
      ניסיונות שגויים והגבלת שליחה נשארות אצלנו (access.phone_lockouts).
   5. פונקציות לשרת: אפשרויות כניסה מוסתרות, פענוח הטלפון לשליחה, זיהוי משתמש, נעילות.
   להריץ אחרי 01, 02 ו-03 (ו-05 בסביבת בדיקות). אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

/* ---------- 1. טריגר היסטוריה: התאמה לפי שם עמודה ---------- */
CREATE OR REPLACE FUNCTION history.tg_save_old_version() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND to_jsonb(NEW) - 'valid_from_utc' = to_jsonb(OLD) - 'valid_from_utc' THEN
        RETURN NULL;
    END IF;
    EXECUTE format('INSERT INTO history.%1$I SELECT * FROM jsonb_populate_record(NULL::history.%1$I, $1)',
                   TG_TABLE_SCHEMA || '_' || TG_TABLE_NAME)
    USING to_jsonb(OLD) || jsonb_build_object(
              'valid_to_utc', now(),
              'operation',    left(TG_OP, 1),
              'changed_by',   coalesce(nullif(current_setting('app.actor', true), ''), session_user::text));
    RETURN NULL;
END $$;

DO $$
DECLARE
    t record;
BEGIN
    FOR t IN
        SELECT n.nspname AS sch, c.relname AS tbl
        FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE  (n.nspname || '_' || c.relname) IN (SELECT relname FROM pg_class WHERE relnamespace = 'history'::regnamespace AND relkind = 'r')
          AND  c.relkind = 'r'
    LOOP
        EXECUTE format($f$
            CREATE OR REPLACE FUNCTION history.%1$I(p_at timestamptz)
            RETURNS SETOF %2$I.%3$I
            LANGUAGE sql STABLE SET search_path = '' AS $body$
                SELECT * FROM %2$I.%3$I WHERE valid_from_utc <= p_at
                UNION ALL
                SELECT (jsonb_populate_record(NULL::%2$I.%3$I, to_jsonb(h))).*
                FROM   history.%4$I h
                WHERE  h.valid_from_utc <= p_at AND h.valid_to_utc > p_at
            $body$ $f$,
            'as_of_' || t.tbl, t.sch, t.tbl, t.sch || '_' || t.tbl);
    END LOOP;
END $$;

/* ---------- 2. קישור למשתמשי Supabase Auth ---------- */
ALTER TABLE core.teachers          ADD COLUMN IF NOT EXISTS auth_user_id uuid NULL REFERENCES auth.users (id) ON DELETE SET NULL;
ALTER TABLE core.supplier_contacts ADD COLUMN IF NOT EXISTS auth_user_id uuid NULL REFERENCES auth.users (id) ON DELETE SET NULL;
ALTER TABLE core.staff_users       ADD COLUMN IF NOT EXISTS auth_user_id uuid NULL REFERENCES auth.users (id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_teachers_auth_user    ON core.teachers (auth_user_id)          WHERE auth_user_id IS NOT NULL;
CREATE INDEX        IF NOT EXISTS ix_supplier_contacts_auth ON core.supplier_contacts (auth_user_id) WHERE auth_user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_staff_users_auth_user ON core.staff_users (auth_user_id)       WHERE auth_user_id IS NOT NULL;

-- גם בטבלאות ההיסטוריה
ALTER TABLE history.core_teachers          ADD COLUMN IF NOT EXISTS auth_user_id uuid NULL;
ALTER TABLE history.core_supplier_contacts ADD COLUMN IF NOT EXISTS auth_user_id uuid NULL;

-- נייד ישראלי מקומי (0501234567) לפורמט של Supabase Auth (972501234567, בלי +)
CREATE OR REPLACE FUNCTION access.to_e164(p_phone text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
    SELECT CASE WHEN p_phone ~ '^05[0-9]{8}$' THEN '972' || substr(p_phone, 2) END
$$;

-- משתמש חדש או עדכון טלפון / מייל ב-Supabase Auth: קישור אוטומטי לרשומה המתאימה אצלנו
CREATE OR REPLACE FUNCTION access.tg_link_auth_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM set_config('app.actor', 'SYSTEM:auth-link', true);
    IF coalesce(NEW.phone, '') <> '' THEN
        UPDATE core.teachers t SET auth_user_id = NEW.id
         WHERE t.is_active AND t.auth_user_id IS NULL AND access.to_e164(t.mobile_phone) = NEW.phone;
        UPDATE core.supplier_contacts c SET auth_user_id = NEW.id
         WHERE c.is_active AND c.auth_user_id IS NULL AND access.to_e164(c.mobile_phone) = NEW.phone;
    END IF;
    IF coalesce(NEW.email, '') <> '' THEN
        UPDATE core.staff_users s SET auth_user_id = NEW.id
         WHERE s.is_active AND s.auth_user_id IS NULL AND lower(s.email) = lower(NEW.email);
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_link_app_user ON auth.users;
CREATE TRIGGER trg_link_app_user AFTER INSERT OR UPDATE OF phone, email ON auth.users
    FOR EACH ROW EXECUTE FUNCTION access.tg_link_auth_user();

-- מי עוד לא קיבל משתמש ב-Supabase Auth (השרת עובר על הרשימה ופותח משתמשים)
CREATE OR REPLACE VIEW access.vw_pending_provisioning WITH (security_invoker = true) AS
SELECT 'TEACHER'::text AS user_type, t.teacher_id AS user_id, t.full_name,
       '+' || access.to_e164(t.mobile_phone) AS phone, NULL::text AS email
FROM   core.teachers t WHERE t.is_active AND t.auth_user_id IS NULL
UNION ALL
SELECT 'SUPPLIER_CONTACT', c.contact_id, c.full_name, '+' || access.to_e164(c.mobile_phone), NULL
FROM   core.supplier_contacts c WHERE c.is_active AND c.can_login AND c.auth_user_id IS NULL
UNION ALL
SELECT 'STAFF', s.staff_user_id, s.full_name, NULL, lower(s.email)
FROM   core.staff_users s WHERE s.is_active AND s.auth_user_id IS NULL;

/* ---------- 3. אישור גננת: ראיה מ-Supabase Auth ---------- */
ALTER TABLE ops.teacher_approvals DROP CONSTRAINT IF EXISTS fk_teacher_approvals_otp;
ALTER TABLE ops.teacher_approvals DROP COLUMN IF EXISTS otp_request_id;
-- בלי FK בכוונה: הראיה נשמרת גם אם המשתמש יימחק מ-Supabase Auth
ALTER TABLE ops.teacher_approvals ADD COLUMN IF NOT EXISTS auth_user_id    uuid NULL;
ALTER TABLE ops.teacher_approvals ADD COLUMN IF NOT EXISTS auth_session_id uuid NULL;  -- session_id מתוך ה-JWT
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ops.teacher_approvals WHERE auth_user_id IS NULL) THEN
        ALTER TABLE ops.teacher_approvals ALTER COLUMN auth_user_id SET NOT NULL;
    END IF;
END $$;

/* ---------- 4. קודים: Supabase מנהל. נעילות והגבלת שליחה: אצלנו ---------- */
DROP TABLE IF EXISTS access.otp_requests;

UPDATE ref.settings SET description_he = 'מספר ספרות בקוד האימות. בפועל נקבע בהגדרות Supabase Auth, וצריך להיות זהה' WHERE setting_key = 'OtpLength';
UPDATE ref.settings SET description_he = 'תוקף קוד אימות בדקות. בפועל נקבע בהגדרות Supabase Auth, וצריך להיות זהה' WHERE setting_key = 'OtpTtlMinutes';
INSERT INTO ref.settings (setting_key, setting_value, value_type, description_he) VALUES
 ('SmsSenderName', 'Ariel', 'TEXT', 'שם השולח בהודעות SMS'),
 ('StaffLoginMethod', 'EMAIL_OTP', 'TEXT', 'צוות אריאל נכנס עם קוד אימות למייל בלבד')
ON CONFLICT (setting_key) DO NOTHING;

-- ערך הגדרה מספרי, עם ברירת מחדל אם חסר
CREATE OR REPLACE FUNCTION ref.setting_int(p_key text, p_default int) RETURNS int
LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT coalesce(max(CASE WHEN setting_value ~ '^[0-9]+$' THEN setting_value::int END), p_default)
    FROM ref.settings WHERE setting_key = p_key
$$;

/* ---------- 5. פונקציות לשרת (service_role בלבד) ---------- */

-- מסך כניסה: הטלפונים המוסתרים של המשתמשים ששייכים לספק / לגן שהוקלד, ורק שלהם.
-- מחזיר רק מי שכבר יש לו משתמש ב-Supabase Auth. אף פעם לא מחזיר מספר מלא.
CREATE OR REPLACE FUNCTION access.login_options(p_user_type text, p_login_key text)
RETURNS TABLE (option_id int, masked_phone text)
LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT c.contact_id, left(c.mobile_phone,3) || '-***' || right(c.mobile_phone,4)
    FROM   core.suppliers s
    JOIN   core.supplier_contacts c ON c.supplier_id = s.supplier_id
    WHERE  p_user_type = 'SUPPLIER_CONTACT'
      AND  s.supplier_number = p_login_key
      AND  s.is_active AND c.is_active AND c.can_login AND c.auth_user_id IS NOT NULL
    UNION ALL
    SELECT t.teacher_id, left(t.mobile_phone,3) || '-***' || right(t.mobile_phone,4)
    FROM   core.kindergartens k
    JOIN   core.teacher_assignments a ON a.kindergarten_id = k.kindergarten_id
    JOIN   core.teachers t            ON t.teacher_id = a.teacher_id
    WHERE  p_user_type = 'TEACHER'
      AND  k.kindergarten_code = p_login_key
      AND  k.is_active AND t.is_active AND t.auth_user_id IS NOT NULL
      AND  a.valid_from <= (now() AT TIME ZONE 'Asia/Jerusalem')::date
      AND (a.valid_to IS NULL OR a.valid_to >= (now() AT TIME ZONE 'Asia/Jerusalem')::date)
    ORDER BY 1
$$;

-- השרת מקבל את הבחירה מהמסך ומפענח את הטלפון המלא לשליחת הקוד (signInWithOtp).
-- מחזיר NULL אם הבחירה לא שייכת לספק / לגן שהוקלד.
CREATE OR REPLACE FUNCTION access.resolve_login_phone(p_user_type text, p_login_key text, p_option_id int)
RETURNS text
LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT '+' || access.to_e164(coalesce(c.mobile_phone, t.mobile_phone))
    FROM   access.login_options(p_user_type, p_login_key) o
    LEFT JOIN core.supplier_contacts c ON p_user_type = 'SUPPLIER_CONTACT' AND c.contact_id = o.option_id
    LEFT JOIN core.teachers t          ON p_user_type = 'TEACHER'          AND t.teacher_id = o.option_id
    WHERE  o.option_id = p_option_id
$$;

-- אחרי כניסה מוצלחת: מי המשתמש ומה מותר לו (לפי auth.uid() שהשרת קיבל מהסשן)
CREATE OR REPLACE FUNCTION access.app_user(p_auth_user_id uuid)
RETURNS TABLE (user_type text, user_id int, full_name text, scope_type text, scope_id int, scope_code text, role_code text)
LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT 'SUPPLIER_CONTACT', c.contact_id, c.full_name::text, 'SUPPLIER', s.supplier_id, s.supplier_number::text, NULL
    FROM   core.supplier_contacts c JOIN core.suppliers s ON s.supplier_id = c.supplier_id
    WHERE  c.auth_user_id = p_auth_user_id AND c.is_active AND c.can_login AND s.is_active
    UNION ALL
    SELECT 'TEACHER', t.teacher_id, t.full_name::text, 'KINDERGARTEN', k.kindergarten_id, k.kindergarten_code::text, NULL
    FROM   core.teachers t
    JOIN   core.teacher_assignments a ON a.teacher_id = t.teacher_id
    JOIN   core.kindergartens k       ON k.kindergarten_id = a.kindergarten_id
    WHERE  t.auth_user_id = p_auth_user_id AND t.is_active AND k.is_active
      AND  a.valid_from <= (now() AT TIME ZONE 'Asia/Jerusalem')::date
      AND (a.valid_to IS NULL OR a.valid_to >= (now() AT TIME ZONE 'Asia/Jerusalem')::date)
    UNION ALL
    SELECT 'STAFF', s.staff_user_id, s.full_name::text, 'ALL', NULL, NULL, r.code::text
    FROM   core.staff_users s JOIN ref.staff_roles r ON r.role_id = s.role_id
    WHERE  s.auth_user_id = p_auth_user_id AND s.is_active
$$;

-- נרמול טלפון לפורמט מקומי (0501234567). מקבל גם +972501234567 או 972501234567.
-- פונקציות הנעילה והגבלת השליחה עובדות בפורמט המקומי, וכך גם יומן ההודעות.
CREATE OR REPLACE FUNCTION access.to_local(p_phone text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
    SELECT CASE
        WHEN p_phone ~ '^\+?9725[0-9]{8}$' THEN '0' || right(p_phone, 9)
        WHEN p_phone ~ '^05[0-9]{8}$'      THEN p_phone
    END
$$;

-- נעילת טלפון: האם נעול עכשיו
CREATE OR REPLACE FUNCTION access.phone_locked_until(p_phone text) RETURNS timestamptz
LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT locked_until FROM access.phone_lockouts
    WHERE  mobile_phone = access.to_local(p_phone) AND locked_until > now()
$$;

-- קוד שגוי: סופר ניסיונות, ונועל אחרי OtpMaxAttempts ל-OtpLockMinutes. מחזיר את זמן סיום הנעילה (או NULL)
CREATE OR REPLACE FUNCTION access.register_failed_attempt(p_phone text) RETURNS timestamptz
LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
    v_max  int := ref.setting_int('OtpMaxAttempts', 3);
    v_lock int := ref.setting_int('OtpLockMinutes', 5);
    v_row  access.phone_lockouts;
    v_ph   text := access.to_local(p_phone);
BEGIN
    IF v_ph IS NULL THEN
        RAISE EXCEPTION 'מספר טלפון לא תקין';
    END IF;
    INSERT INTO access.phone_lockouts AS p (mobile_phone, failed_attempts, last_failed_at)
    VALUES (v_ph, 1, now())
    ON CONFLICT (mobile_phone) DO UPDATE
        SET failed_attempts = CASE WHEN p.locked_until IS NOT NULL AND p.locked_until <= now() THEN 1
                                   ELSE p.failed_attempts + 1 END,
            locked_until    = CASE WHEN p.locked_until IS NOT NULL AND p.locked_until <= now() THEN NULL
                                   ELSE p.locked_until END,
            last_failed_at  = now()
    RETURNING * INTO v_row;

    IF v_row.failed_attempts >= v_max AND (v_row.locked_until IS NULL OR v_row.locked_until <= now()) THEN
        UPDATE access.phone_lockouts SET locked_until = now() + make_interval(mins => v_lock)
        WHERE mobile_phone = v_ph RETURNING locked_until INTO v_row.locked_until;
    END IF;
    RETURN v_row.locked_until;
END $$;

-- כניסה מוצלחת: איפוס ניסיונות
CREATE OR REPLACE FUNCTION access.reset_failed_attempts(p_phone text) RETURNS void
LANGUAGE sql SET search_path = '' AS $$
    DELETE FROM access.phone_lockouts WHERE mobile_phone = access.to_local(p_phone)
$$;

-- הגבלת שליחה: האם מותר לשלוח עוד קוד לנייד בשעה האחרונה (לפי יומן ההודעות)
-- השרת רושם כל בקשת קוד ב-ops.notifications עם purpose = 'OTP' ו-destination בפורמט מקומי
CREATE OR REPLACE FUNCTION access.can_send_otp(p_phone text) RETURNS boolean
LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT access.phone_locked_until(p_phone) IS NULL
       AND (SELECT count(*) FROM ops.notifications n
            WHERE n.purpose = 'OTP' AND n.destination = access.to_local(p_phone)
              AND n.created_at > now() - interval '1 hour') < ref.setting_int('OtpMaxSendsPerHour', 5)
$$;

/* ---------- הרשאות: רק service_role ---------- */
DO $$
DECLARE
    sch text;
BEGIN
    FOREACH sch IN ARRAY ARRAY['ref','core','ops','access','history'] LOOP
        EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA %I FROM PUBLIC', sch);
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
            EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM anon, authenticated', sch);
            EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA %I FROM anon, authenticated', sch);
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
            EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA %I TO service_role', sch);
            EXECUTE format('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA %I TO service_role', sch);
        END IF;
    END LOOP;
    -- הטריגר על auth.users רץ בהקשר של Supabase Auth
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
        GRANT USAGE ON SCHEMA access TO supabase_auth_admin;
        GRANT EXECUTE ON FUNCTION access.tg_link_auth_user() TO supabase_auth_admin;
    END IF;
END $$;

COMMIT;

SELECT '07_supabase_auth.sql הושלם' AS status;
