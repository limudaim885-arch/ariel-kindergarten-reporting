/* =====================================================================
   15_teacher_confirm_only.sql  |  PostgreSQL (Supabase)
   אישור גננת בסימון "אני מאשרת" בלבד, בלי הקלדת שם
   ---------------------------------------------------------------------
   access.teacher_decide כבר לא דורשת שם מוקלד כדי לאשר. הראיה לאישור נשארת:
   הגננת שנכנסה עם קוד SMS, הנייד שלה, מזהה הסשן, כתובת הרשת, ה-User-Agent
   וטביעת התוכן של הדיווח (ops.teacher_approvals).

   החתימה (רשימת הפרמטרים) לא השתנתה, כדי שהקוד שכבר באוויר ימשיך לעבוד
   בזמן ההחלפה. p_signed_name לא חובה: הקוד החדש שולח NULL, ואם נשלח שם הוא
   נשמר בהערה כמו קודם. כל שאר הבדיקות זהות ל-14.

   להריץ אחרי 14. אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

-- ---------------------------------------------------------------------
-- אישור או החזרה של דיווח
--    p_decision: 'APPROVED' | 'REJECTED'
--    אישור: לא דורש פרטים נוספים (הסימון "אני מאשרת" נבדק בשרת האפליקציה).
--    החזרה: דורשת סיבה של גננת (p_reason_id). בסיבה "אחר" חובה הערה.
--    מחזירה {"ok": true, "status"} או {"ok": false, "message"}.
--    דיווח שאינו בגן של הגננת, או קלט לא תקין, עוצרים עם שגיאה כללית.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.teacher_decide(
    p_auth_user_id uuid,
    p_report_id    integer,
    p_decision     text,
    p_reason_id    smallint,
    p_comment      text,
    p_signed_name  text,
    p_session_id   uuid,
    p_ip           text,
    p_user_agent   text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO ''
AS $function$
DECLARE
    v_teacher_id  integer;
    v_phone       char(10);
    v_today       date := (now() AT TIME ZONE 'Asia/Jerusalem')::date;
    v_comment     text := nullif(btrim(coalesce(p_comment, '')), '');
    v_signed      text := nullif(btrim(coalesce(p_signed_name, '')), '');
    v_reason_name text;
    v_rep         record;
    v_new         smallint;
    v_new_code    text;
BEGIN
    SELECT t.teacher_id, t.mobile_phone
      INTO v_teacher_id, v_phone
      FROM core.teachers t
     WHERE t.auth_user_id = p_auth_user_id AND t.is_active
     ORDER BY t.teacher_id
     LIMIT 1;

    IF v_teacher_id IS NULL THEN
        RAISE EXCEPTION 'not a teacher' USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.actor', 'TEACHER:' || v_teacher_id, true);

    IF p_decision IS NULL OR p_decision NOT IN ('APPROVED', 'REJECTED')
       OR p_report_id IS NULL OR length(coalesce(v_comment, '')) > 450 THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    IF p_decision = 'APPROVED' THEN
        -- The teacher confirms with the "אני מאשרת" checkbox only. A typed name,
        -- if a caller still sends one, is kept in the comment.
        v_comment := CASE WHEN v_signed IS NOT NULL THEN 'חתימה: ' || left(v_signed, 100) END;
    ELSE
        SELECT rr.name_he INTO v_reason_name
          FROM ref.rejection_reasons rr
         WHERE rr.rejection_reason_id = p_reason_id AND rr.applies_to = 'TEACHER' AND rr.is_active;
        IF v_reason_name IS NULL THEN
            RETURN jsonb_build_object('ok', false, 'message', 'יש לבחור את הסיבה להחזרת הדיווח.');
        END IF;
        IF v_reason_name = 'אחר' AND v_comment IS NULL THEN
            RETURN jsonb_build_object('ok', false, 'message', 'כשבוחרים "אחר" יש לכתוב מה הבעיה בדיווח.');
        END IF;
    END IF;

    -- הדיווח, רק אם הוא בגן שהגננת משובצת אליו היום. הנעילה מונעת שתי החלטות במקביל
    SELECT r.report_id, r.status_id, r.is_manual, st.code, st.name_he, k.is_manual_track
      INTO v_rep
      FROM ops.reports r
      JOIN core.engagements e     ON e.engagement_id = r.engagement_id
      JOIN core.kindergartens k   ON k.kindergarten_id = e.kindergarten_id
      JOIN ref.report_statuses st ON st.status_id = r.status_id
     WHERE r.report_id = p_report_id
       AND k.is_active
       AND EXISTS (SELECT 1 FROM core.teacher_assignments a
                    WHERE a.teacher_id = v_teacher_id
                      AND a.kindergarten_id = k.kindergarten_id
                      AND a.valid_from <= v_today
                      AND (a.valid_to IS NULL OR a.valid_to >= v_today))
       FOR UPDATE OF r;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    IF v_rep.is_manual OR v_rep.is_manual_track THEN
        RETURN jsonb_build_object('ok', false, 'message', 'הדיווח הזה במסלול טופס ידני, ולא נחתם כאן.');
    END IF;

    IF v_rep.code <> 'SENT_TO_TEACHER' THEN
        RETURN jsonb_build_object('ok', false,
            'message', 'הדיווח כבר טופל (' || v_rep.name_he || '). אין צורך לעשות דבר נוסף.');
    END IF;

    v_new_code := CASE p_decision WHEN 'APPROVED' THEN 'TEACHER_APPROVED' ELSE 'TEACHER_REJECTED' END;
    SELECT status_id INTO v_new FROM ref.report_statuses WHERE code = v_new_code;

    INSERT INTO ops.teacher_approvals (report_id, teacher_id, decision, phone_used, ip_address, user_agent,
                                       content_hash, rejection_reason_id, comment, auth_user_id, auth_session_id)
    VALUES (p_report_id, v_teacher_id, p_decision, v_phone, left(p_ip, 45), left(p_user_agent, 400),
            ops.report_content_hash(p_report_id),
            CASE WHEN p_decision = 'REJECTED' THEN p_reason_id END,
            v_comment, p_auth_user_id, p_session_id);

    UPDATE ops.reports
       SET status_id = v_new, updated_at = now()
     WHERE report_id = p_report_id;

    INSERT INTO ops.report_status_history (report_id, from_status_id, to_status_id, actor_type, actor_id,
                                           rejection_reason_id, comment)
    VALUES (p_report_id, v_rep.status_id, v_new, 'TEACHER', v_teacher_id,
            CASE WHEN p_decision = 'REJECTED' THEN p_reason_id END,
            CASE WHEN p_decision = 'REJECTED' THEN v_comment END);

    RETURN jsonb_build_object('ok', true, 'status', v_new_code);
END $function$;

REVOKE ALL ON FUNCTION access.teacher_decide(uuid, integer, text, smallint, text, text, uuid, text, text) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION access.teacher_decide(uuid, integer, text, smallint, text, text, uuid, text, text)
            FROM anon, authenticated;
        GRANT EXECUTE ON FUNCTION access.teacher_decide(uuid, integer, text, smallint, text, text, uuid, text, text)
            TO service_role;
    END IF;
END $$;

COMMIT;
