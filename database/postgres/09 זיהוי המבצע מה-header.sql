/* =====================================================================
   09_actor_from_header.sql  |  PostgreSQL (Supabase)
   "מי שינה" בהיסטוריה, גם כשהשרת עובד דרך ה-API של Supabase (rpc / PostgREST)
   ---------------------------------------------------------------------
   דרך ה-API כל קריאה היא טרנזקציה נפרדת, ולכן set_config('app.actor') לא נשמר
   מקריאה לקריאה. השרת שולח במקום זה header בשם x-app-actor (למשל 'STAFF:12'),
   ו-PostgREST חושף את ה-headers למסד דרך current_setting('request.headers').

   סדר העדיפויות לזהות המבצע:
   1. app.actor  (set_config בתוך אותה טרנזקציה, למשל בפונקציות מרובות שלבים או בייבוא)
   2. x-app-actor מה-header של הבקשה (רק בפורמט TYPE:ID)
   3. שם המשתמש של מסד הנתונים
   להריץ אחרי 07. אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

CREATE OR REPLACE FUNCTION history.current_actor() RETURNS text
LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE
    v_actor   text := nullif(current_setting('app.actor', true), '');
    v_headers text;
BEGIN
    IF v_actor IS NULL THEN
        v_headers := nullif(current_setting('request.headers', true), '');
        IF v_headers IS NOT NULL THEN
            BEGIN
                v_actor := v_headers::jsonb ->> 'x-app-actor';
            EXCEPTION WHEN others THEN
                v_actor := NULL;   -- header לא תקין לא עוצר את הפעולה
            END;
            IF v_actor IS NOT NULL AND v_actor !~ '^[A-Z_]{2,20}:[A-Za-z0-9_-]{1,40}$' THEN
                v_actor := NULL;
            END IF;
        END IF;
    END IF;
    RETURN left(coalesce(v_actor, session_user::text), 100);
END $$;

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
              'changed_by',   history.current_actor());
    RETURN NULL;
END $$;

REVOKE ALL ON FUNCTION history.current_actor() FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION history.current_actor() FROM anon, authenticated;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        GRANT EXECUTE ON FUNCTION history.current_actor() TO service_role;
    END IF;
END $$;

COMMIT;

SELECT '09_actor_from_header.sql הושלם' AS status;
