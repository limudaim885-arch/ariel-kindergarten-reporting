/* =====================================================================
   02_enable_history.sql  |  שלב א'  |  גרסת PostgreSQL (Supabase)
   היסטוריית שינויים אוטומטית
   ---------------------------------------------------------------------
   ב-SQL Server זה נעשה עם System-Versioned Temporal Tables.
   ל-PostgreSQL אין תכונה כזו, ולכן היא נבנית כאן עם טריגרים, באותו עיקרון:
   * לכל טבלה במעקב נוספת עמודה valid_from_utc (מתי הגרסה הנוכחית התחילה).
   * בכל עדכון או מחיקה, הגרסה הקודמת של השורה נשמרת בטבלת היסטוריה
     history.<סכמה>_<טבלה>, עם valid_from_utc, valid_to_utc, סוג הפעולה ומי ביצע.
   * תוספת על המקור: נשמר גם מי שינה (changed_by). האפליקציה צריכה להריץ
     בתחילת כל טרנזקציה:  SELECT set_config('app.actor', 'STAFF:12', true);
     אם לא הוגדר, נרשם שם המשתמש של מסד הנתונים.

   דוגמה: מה היה התעריף של התקשרות 15 ב-1 בינואר 2026 (שעון ישראל)?
     SELECT * FROM history.as_of_engagements('2026-01-01 00:00 Asia/Jerusalem') WHERE engagement_id = 15;

   אם מוסיפים עמודה לטבלה במעקב, צריך להוסיף אותה גם לטבלת ההיסטוריה שלה
   (בכל מיקום). אם שוכחים, הטריגר לא ייכשל, אבל ערך העמודה החדשה לא יישמר בהיסטוריה.
   להריץ אחרי 01.
   ===================================================================== */

BEGIN;

CREATE SCHEMA IF NOT EXISTS history;

-- טריגר לפני עדכון: מעדכן את valid_from_utc של הגרסה החדשה
CREATE OR REPLACE FUNCTION history.tg_set_valid_from() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    NEW.valid_from_utc := now();
    RETURN NEW;
END $$;

-- טריגר אחרי עדכון / מחיקה: שומר את הגרסה הקודמת בטבלת ההיסטוריה
CREATE OR REPLACE FUNCTION history.tg_save_old_version() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    -- עדכון שלא שינה שום ערך לא נרשם
    IF TG_OP = 'UPDATE' AND to_jsonb(NEW) - 'valid_from_utc' = to_jsonb(OLD) - 'valid_from_utc' THEN
        RETURN NULL;
    END IF;
    -- התאמה לפי שם עמודה ולא לפי מיקום, כך שהוספת עמודה לטבלה לא שוברת את הטריגר
    EXECUTE format('INSERT INTO history.%1$I SELECT * FROM jsonb_populate_record(NULL::history.%1$I, $1)',
                   TG_TABLE_SCHEMA || '_' || TG_TABLE_NAME)
    USING to_jsonb(OLD) || jsonb_build_object(
              'valid_to_utc', now(),
              'operation',    left(TG_OP, 1),   -- U = עדכון, D = מחיקה
              'changed_by',   coalesce(nullif(current_setting('app.actor', true), ''), session_user::text));
    RETURN NULL;
END $$;

DO $$
DECLARE
    t   record;
    h   text;
BEGIN
    FOR t IN
        SELECT * FROM (VALUES
            ('core', 'suppliers'),
            ('core', 'supplier_contacts'),
            ('core', 'kindergartens'),
            ('core', 'teachers'),
            ('core', 'teacher_assignments'),
            ('core', 'engagements'),
            ('core', 'work_orders'),
            ('ref',  'settings')
        ) AS v (sch, tbl)
    LOOP
        h := t.sch || '_' || t.tbl;
        IF to_regclass(format('history.%I', h)) IS NOT NULL THEN
            CONTINUE;   -- כבר הופעל
        END IF;

        -- עמודת התחלת תוקף בטבלה עצמה
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN valid_from_utc timestamptz(0) NOT NULL DEFAULT now()', t.sch, t.tbl);

        -- טבלת היסטוריה: אותן עמודות (בלי אילוצים ייחודיים), ועוד עמודות היסטוריה
        EXECUTE format('CREATE TABLE history.%I (LIKE %I.%I INCLUDING DEFAULTS EXCLUDING IDENTITY)', h, t.sch, t.tbl);
        EXECUTE format('ALTER TABLE history.%I
                            ADD COLUMN valid_to_utc timestamptz(0) NOT NULL,
                            ADD COLUMN operation  char(1)        NOT NULL CHECK (operation IN (''U'',''D'')),
                            ADD COLUMN changed_by varchar(100)   NULL', h);
        EXECUTE format('CREATE INDEX %I ON history.%I (valid_from_utc, valid_to_utc)', 'ix_' || h || '_period', h);
        EXECUTE format('ALTER TABLE history.%I ENABLE ROW LEVEL SECURITY', h);

        EXECUTE format('CREATE TRIGGER trg_history_valid_from BEFORE UPDATE ON %I.%I
                            FOR EACH ROW EXECUTE FUNCTION history.tg_set_valid_from()', t.sch, t.tbl);
        EXECUTE format('CREATE TRIGGER trg_history_save AFTER UPDATE OR DELETE ON %I.%I
                            FOR EACH ROW EXECUTE FUNCTION history.tg_save_old_version()', t.sch, t.tbl);

        -- פונקציית "מצב בנקודת זמן" (במקור: FOR SYSTEM_TIME AS OF)
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
            'as_of_' || t.tbl, t.sch, t.tbl, h);

        RAISE NOTICE 'היסטוריה הופעלה: %.%', t.sch, t.tbl;
    END LOOP;
END $$;

-- הרשאות: כמו בשאר המסד, רק service_role
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA history FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON SCHEMA history FROM anon, authenticated;
        REVOKE ALL ON ALL TABLES IN SCHEMA history FROM anon, authenticated;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        GRANT USAGE ON SCHEMA history TO service_role;
        GRANT ALL ON ALL TABLES IN SCHEMA history TO service_role;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA history TO service_role;
    END IF;
END $$;

COMMIT;

SELECT '02_enable_history.sql הושלם' AS status;
