/* =====================================================================
   11_sms_provider_019.sql  |  PostgreSQL (Supabase)
   ספק ה-SMS הוא 019 (דרך Send SMS Hook של Supabase Auth). mgroup כבר לא רלוונטי.
   ---------------------------------------------------------------------
   מעדכן סביבה קיימת שבה 03 ו-08 הורצו לפני ההחלפה:
   1. ההגדרה SmsProvider ב-ref.settings: mgroup ← 019.
   2. הודעת השגיאה של ה-hook הזמני access.send_sms_hook.
   בסביבה חדשה אין צורך להריץ: 03 ו-08 כבר כוללים את 019.
   כבר הורץ על פרויקט הבדיקות ב-Supabase (24.11.2026).
   אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

SELECT set_config('app.actor', 'MIGRATION:11', true);

UPDATE ref.settings
   SET setting_value = '019'
 WHERE setting_key = 'SmsProvider'
   AND setting_value = 'mgroup';

CREATE OR REPLACE FUNCTION access.send_sms_hook(event jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    RETURN jsonb_build_object('error', jsonb_build_object(
        'http_code', 503,
        'message',   'SMS sending is not connected yet (019)'));
END $function$;

COMMIT;
