/* =====================================================================
   14_teacher_screens.sql  |  PostgreSQL (Supabase)
   פונקציות השרת למסכי הגננת באפליקציה
   ---------------------------------------------------------------------
   ops.report_content_hash(report_id)
       טביעת תוכן (SHA-256) של דיווח: ההתקשרות, החודש, וכל שורה עם תאריך,
       סוג מפגש ותעריף. נשמרת באישור הגננת, והרפרנטית יכולה לחשב אותה שוב
       ולוודא שהתוכן לא השתנה מאז החתימה.
   access.teacher_data(auth_user_id)
       הגננת, הגנים שהיא משובצת אליהם היום, סיבות ההחזרה, והדיווחים של הגנים
       האלה ב-12 החודשים האחרונים.
   access.teacher_decide(auth_user_id, report_id, decision, ...)
       אישור או החזרה של דיווח שממתין לחתימה. שומרת ראיה ב-ops.teacher_approvals
       (נייד, סשן, כתובת רשת, User-Agent, טביעת תוכן), מעדכנת את הסטטוס
       ורושמת את המעבר בהיסטוריה, בטרנזקציה אחת.

   כל גננת שמשובצת היום לגן (כולל ממלאת מקום) רואה וחותמת. הראשונה שחותמת קובעת.
   הגננת מזוהה רק לפי auth_user_id שהשרת לוקח מהסשן.
   רק service_role (צד השרת) יכול להריץ. להריץ אחרי 07 ו-13. אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

-- ---------------------------------------------------------------------
-- 1. טביעת תוכן של דיווח
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ops.report_content_hash(p_report_id integer)
 RETURNS bytea
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT sha256(convert_to(
               r.report_id || '|' || r.engagement_id || '|' || r.report_year || '-' || r.report_month || '|'
               || coalesce((SELECT string_agg(l.visit_date::text || ':' || st.code || ':' || l.tariff_applied::text,
                                              ',' ORDER BY l.visit_date)
                              FROM ops.report_lines l
                              JOIN ref.session_types st ON st.session_type_id = l.session_type_id
                             WHERE l.report_id = r.report_id), ''),
               'UTF8'))
      FROM ops.reports r
     WHERE r.report_id = p_report_id;
$function$;


-- ---------------------------------------------------------------------
-- 2. הנתונים של מסכי הגננת
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.teacher_data(p_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
    v_teacher_id integer;
    v_name       text;
    v_today      date := (now() AT TIME ZONE 'Asia/Jerusalem')::date;
    v_from       integer;  -- year * 12 + month, 12 חודשים אחורה
BEGIN
    SELECT t.teacher_id, t.full_name
      INTO v_teacher_id, v_name
      FROM core.teachers t
     WHERE t.auth_user_id = p_auth_user_id AND t.is_active
     ORDER BY t.teacher_id
     LIMIT 1;

    IF v_teacher_id IS NULL THEN
        RAISE EXCEPTION 'not a teacher' USING ERRCODE = '42501';
    END IF;

    v_from := extract(year FROM v_today)::int * 12 + extract(month FROM v_today)::int - 12;

    RETURN jsonb_build_object(
        'teacher', jsonb_build_object('teacher_id', v_teacher_id, 'full_name', v_name),
        'today',   v_today,

        'kindergartens', coalesce((
            SELECT jsonb_agg(jsonb_build_object('kindergarten_id', k.kindergarten_id,
                                                'code', k.kindergarten_code,
                                                'name', k.name,
                                                'is_manual_track', k.is_manual_track,
                                                'is_substitute', a.is_substitute)
                             ORDER BY k.name)
              FROM core.teacher_assignments a
              JOIN core.kindergartens k ON k.kindergarten_id = a.kindergarten_id
             WHERE a.teacher_id = v_teacher_id
               AND k.is_active
               AND a.valid_from <= v_today
               AND (a.valid_to IS NULL OR a.valid_to >= v_today)), '[]'::jsonb),

        'reasons', coalesce((
            SELECT jsonb_agg(jsonb_build_object('id', rr.rejection_reason_id, 'name', rr.name_he)
                             ORDER BY rr.rejection_reason_id)
              FROM ref.rejection_reasons rr
             WHERE rr.applies_to = 'TEACHER' AND rr.is_active), '[]'::jsonb),

        'reports', coalesce((
            SELECT jsonb_agg(x.j ORDER BY x.report_year DESC, x.report_month DESC, x.report_id DESC)
              FROM (SELECT r.report_year, r.report_month, r.report_id,
                           jsonb_build_object(
                               'report_id', r.report_id,
                               'year', r.report_year,
                               'month', r.report_month,
                               'status', st.code,
                               'status_name', st.name_he,
                               'is_manual', r.is_manual,
                               'submitted_at', r.submitted_at,
                               'kindergarten', jsonb_build_object('kindergarten_id', k.kindergarten_id,
                                                                  'code', k.kindergarten_code,
                                                                  'name', k.name,
                                                                  'is_manual_track', k.is_manual_track),
                               'supplier', jsonb_build_object('name', s.name),
                               'domain', d.name_he,
                               'engagement_type', et.name_he,
                               'tariff', e.tariff_per_session,
                               'sessions', coalesce(l.sessions, 0),
                               'amount', coalesce(l.amount, 0),
                               'lines', coalesce(l.lines, '[]'::jsonb),
                               'decision', ta.decision
                           ) AS j
                      FROM ops.reports r
                      JOIN core.engagements e      ON e.engagement_id = r.engagement_id
                      JOIN core.kindergartens k    ON k.kindergarten_id = e.kindergarten_id
                      JOIN core.suppliers s        ON s.supplier_id = e.supplier_id
                      JOIN ref.activity_domains d  ON d.domain_id = e.domain_id
                      JOIN ref.engagement_types et ON et.engagement_type_id = e.engagement_type_id
                      JOIN ref.report_statuses st  ON st.status_id = r.status_id
                      LEFT JOIN LATERAL (
                           SELECT sum(rl.cap_units)::int AS sessions,
                                  sum(rl.line_amount)    AS amount,
                                  jsonb_agg(jsonb_build_object('date', rl.visit_date,
                                                               'double', stp.code = 'DOUBLE',
                                                               'amount', rl.line_amount,
                                                               'flagged', rl.is_holiday_flag)
                                            ORDER BY rl.visit_date) AS lines
                             FROM ops.report_lines rl
                             JOIN ref.session_types stp ON stp.session_type_id = rl.session_type_id
                            WHERE rl.report_id = r.report_id) l ON true
                      LEFT JOIN LATERAL (   -- ההחלטה האחרונה של גננת על הדיווח
                           SELECT jsonb_build_object('decision', a.decision,
                                                     'decided_at', a.decided_at,
                                                     'teacher_name', t.full_name,
                                                     'reason', rr.name_he,
                                                     'comment', a.comment) AS decision
                             FROM ops.teacher_approvals a
                             JOIN core.teachers t ON t.teacher_id = a.teacher_id
                             LEFT JOIN ref.rejection_reasons rr ON rr.rejection_reason_id = a.rejection_reason_id
                            WHERE a.report_id = r.report_id
                            ORDER BY a.decided_at DESC, a.teacher_approval_id DESC
                            LIMIT 1) ta ON true
                     WHERE st.code <> 'DRAFT'
                       AND r.report_year * 12 + r.report_month >= v_from
                       AND EXISTS (SELECT 1 FROM core.teacher_assignments a
                                    WHERE a.teacher_id = v_teacher_id
                                      AND a.kindergarten_id = k.kindergarten_id
                                      AND a.valid_from <= v_today
                                      AND (a.valid_to IS NULL OR a.valid_to >= v_today))
                       AND k.is_active) x), '[]'::jsonb)
    );
END $function$;


-- ---------------------------------------------------------------------
-- 3. אישור או החזרה של דיווח
--    p_decision: 'APPROVED' | 'REJECTED'
--    אישור: דורש שם מלא מוקלד (p_signed_name), שנשמר בהערת האישור.
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
        IF v_signed IS NULL OR length(v_signed) > 100 THEN
            RETURN jsonb_build_object('ok', false, 'message', 'יש להקליד את שמך המלא כדי לחתום.');
        END IF;
        v_comment := 'חתימה: ' || v_signed;
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


-- ---------------------------------------------------------------------
-- 4. הרשאות: רק service_role (צד השרת)
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION ops.report_content_hash(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION access.teacher_data(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION access.teacher_decide(uuid, integer, text, smallint, text, text, uuid, text, text) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION ops.report_content_hash(integer) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION access.teacher_data(uuid) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION access.teacher_decide(uuid, integer, text, smallint, text, text, uuid, text, text)
            FROM anon, authenticated;
        GRANT EXECUTE ON FUNCTION ops.report_content_hash(integer) TO service_role;
        GRANT EXECUTE ON FUNCTION access.teacher_data(uuid) TO service_role;
        GRANT EXECUTE ON FUNCTION access.teacher_decide(uuid, integer, text, smallint, text, text, uuid, text, text)
            TO service_role;
    END IF;
END $$;

COMMIT;
