/* =====================================================================
   12_health_check.sql  |  PostgreSQL (Supabase)
   פונקציה לבדיקת תקינות, בשביל /api/health באפליקציה.
   ---------------------------------------------------------------------
   access.health_check() קוראת שורה אחת מ-ref.settings ומחזירה true.
   אם המסד לא זמין, הקריאה נכשלת והאפליקציה מחזירה 503.
   לא מחזירה שום נתון. רק service_role (צד השרת) יכול להריץ אותה.
   להריץ אחרי 07 (הסכמה access חשופה ב-Data API). אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

CREATE OR REPLACE FUNCTION access.health_check()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT EXISTS (SELECT 1 FROM ref.settings);
$function$;

REVOKE ALL ON FUNCTION access.health_check() FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION access.health_check() FROM anon, authenticated;
        GRANT EXECUTE ON FUNCTION access.health_check() TO service_role;
    END IF;
END $$;

COMMIT;
