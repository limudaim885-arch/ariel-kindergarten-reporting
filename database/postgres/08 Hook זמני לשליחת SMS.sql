/* =====================================================================
   08_sms_hook_placeholder.sql  |  PostgreSQL (Supabase)
   Send SMS Hook זמני, עד שה-API של mgroup יהיה זמין.
   ---------------------------------------------------------------------
   Supabase Auth קורא לפונקציה הזו במקום לשלוח SMS בעצמו.
   כרגע היא מחזירה שגיאה ברורה ("שליחת SMS עדיין לא מחוברת"), כך שאף קוד
   לא הולך לאיבוד בשקט, ואף קוד לא נשמר במסד.
   לבדיקות פיתוח משתמשים ב"Test Phone Numbers" בהגדרות ה-Phone ב-Supabase.
   כשה-API של mgroup יגיע: מחליפים את ה-Hook ל-HTTP שמפנה ל-Edge Function
   ששולחת דרך mgroup (שם שולח Ariel), ומוחקים את הפונקציה הזו.
   ===================================================================== */

CREATE OR REPLACE FUNCTION access.send_sms_hook(event jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    RETURN jsonb_build_object('error', jsonb_build_object(
        'http_code', 503,
        'message',   'SMS sending is not connected yet (mgroup)'));
END $$;

GRANT USAGE ON SCHEMA access TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION access.send_sms_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION access.send_sms_hook(jsonb) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE EXECUTE ON FUNCTION access.send_sms_hook(jsonb) FROM anon, authenticated;
    END IF;
END $$;

SELECT '08_sms_hook_placeholder.sql הושלם' AS status;
