/* =====================================================================
   16_staff_screens.sql  |  PostgreSQL (Supabase)
   פונקציות השרת למסכי הרפרנטית באפליקציה
   ---------------------------------------------------------------------
   ops.staff_member(auth_user_id)
       איש הצוות הפעיל לפי חשבון הכניסה: מזהה, שם ותפקיד. פונקציית עזר פנימית.
   access.staff_reports(auth_user_id)
       כל הדיווחים (בלי שורות) מ-12 החודשים האחרונים, וכל דיווח פתוח גם אם ישן יותר.
       משמשת למסך הראשי, לתור האישורים ולרשימת הדיווחים.
   access.staff_report(auth_user_id, report_id)
       דיווח אחד במלואו: שורות, ניצול התקרה, אישורי הגננת (כולל בדיקה שהתוכן
       לא השתנה מאז האישור) והיסטוריית הסטטוסים.
   access.staff_decide(auth_user_id, report_id, decision, reason_id, comment)
       אישור סופי ונעילה, או החזרה לספק לתיקון. רק לדיווח שהגננת אישרה.
       הנעילה מכניסה את הדיווח לתור של פרוסי (הטריגר trg_reports_enqueue_procy).
   access.staff_caps(auth_user_id)
       התקשרויות פעילות שקרובות לתקרה או הגיעו אליה, עם החריגות שכבר אושרו.
   access.staff_add_cap_override(auth_user_id, engagement_id, extra_sessions, extra_amount, reason)
       אישור חריגה מתקרה (core.cap_overrides).

   הרשאות: כל איש צוות פעיל רואה הכול. מנהלת מערכת ורפרנטית מאשרות, נועלות
   ומאשרות חריגות. תפקיד "צפייה בלבד" רק רואה.
   איש הצוות מזוהה רק לפי auth_user_id שהשרת לוקח מהסשן.
   רק service_role (צד השרת) יכול להריץ. להריץ אחרי 15. אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

-- ---------------------------------------------------------------------
-- 1. איש הצוות לפי חשבון הכניסה
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ops.staff_member(p_auth_user_id uuid)
 RETURNS TABLE (staff_user_id integer, full_name text, role_code text, can_act boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    SELECT s.staff_user_id, s.full_name::text, r.code::text, r.code IN ('ADMIN', 'REFERENT')
      FROM core.staff_users s
      JOIN ref.staff_roles r ON r.role_id = s.role_id
     WHERE s.auth_user_id = p_auth_user_id AND s.is_active
     ORDER BY s.staff_user_id
     LIMIT 1;
$function$;

-- ---------------------------------------------------------------------
-- 2. רשימת הדיווחים
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.staff_reports(p_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
    v_staff record;
    v_today date := (now() AT TIME ZONE 'Asia/Jerusalem')::date;
    v_from  integer;
BEGIN
    SELECT * INTO v_staff FROM ops.staff_member(p_auth_user_id);
    IF v_staff.staff_user_id IS NULL THEN
        RAISE EXCEPTION 'not staff' USING ERRCODE = '42501';
    END IF;

    v_from := extract(year FROM v_today)::int * 12 + extract(month FROM v_today)::int - 12;

    RETURN jsonb_build_object(
        'staff', to_jsonb(v_staff),
        'today', v_today,
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
                               'updated_at', r.updated_at,
                               'kindergarten', jsonb_build_object('kindergarten_id', k.kindergarten_id,
                                                                  'code', k.kindergarten_code,
                                                                  'name', k.name,
                                                                  'is_manual_track', k.is_manual_track,
                                                                  'is_mine', k.referent_staff_user_id = v_staff.staff_user_id),
                               'supplier', jsonb_build_object('supplier_id', s.supplier_id,
                                                              'number', s.supplier_number,
                                                              'name', s.name),
                               'domain', d.name_he,
                               'sessions', coalesce(l.sessions, 0),
                               'amount', coalesce(l.amount, 0),
                               'teacher_decision', ta.j
                           ) AS j
                      FROM ops.reports r
                      JOIN core.engagements e     ON e.engagement_id = r.engagement_id
                      JOIN core.kindergartens k   ON k.kindergarten_id = e.kindergarten_id
                      JOIN core.suppliers s       ON s.supplier_id = e.supplier_id
                      JOIN ref.activity_domains d ON d.domain_id = e.domain_id
                      JOIN ref.report_statuses st ON st.status_id = r.status_id
                      LEFT JOIN LATERAL (
                           SELECT sum(rl.cap_units)::int AS sessions, sum(rl.line_amount) AS amount
                             FROM ops.report_lines rl
                            WHERE rl.report_id = r.report_id) l ON true
                      LEFT JOIN LATERAL (
                           SELECT jsonb_build_object('decision', a.decision,
                                                     'decided_at', a.decided_at,
                                                     'teacher_name', t.full_name) AS j
                             FROM ops.teacher_approvals a
                             JOIN core.teachers t ON t.teacher_id = a.teacher_id
                            WHERE a.report_id = r.report_id
                            ORDER BY a.decided_at DESC, a.teacher_approval_id DESC
                            LIMIT 1) ta ON true
                     WHERE st.code <> 'DRAFT'
                       AND (r.report_year * 12 + r.report_month >= v_from
                            OR st.code NOT IN ('STAFF_APPROVED', 'LOCKED'))) x), '[]'::jsonb)
    );
END $function$;

-- ---------------------------------------------------------------------
-- 3. דיווח אחד במלואו
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.staff_report(p_auth_user_id uuid, p_report_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
    v_staff  record;
    v_hash   bytea;
    v_report jsonb;
BEGIN
    SELECT * INTO v_staff FROM ops.staff_member(p_auth_user_id);
    IF v_staff.staff_user_id IS NULL THEN
        RAISE EXCEPTION 'not staff' USING ERRCODE = '42501';
    END IF;

    v_hash := ops.report_content_hash(p_report_id);

    SELECT jsonb_build_object(
               'report_id', r.report_id,
               'year', r.report_year,
               'month', r.report_month,
               'status', st.code,
               'status_name', st.name_he,
               'is_manual', r.is_manual,
               'submitted_at', r.submitted_at,
               'final_approved_at', r.final_approved_at,
               'final_approved_by', fa.full_name,
               'locked_at', r.locked_at,
               'kindergarten', jsonb_build_object('kindergarten_id', k.kindergarten_id,
                                                  'code', k.kindergarten_code,
                                                  'name', k.name,
                                                  'is_manual_track', k.is_manual_track,
                                                  'is_mine', k.referent_staff_user_id = v_staff.staff_user_id),
               'supplier', jsonb_build_object('supplier_id', s.supplier_id, 'number', s.supplier_number, 'name', s.name),
               'submitted_by', sc.full_name,
               'domain', d.name_he,
               'engagement_type', et.name_he,
               'engagement_id', e.engagement_id,
               'tariff', e.tariff_per_session,
               'usage', jsonb_build_object('session_cap', u.session_cap, 'sessions_used', u.sessions_used,
                                           'amount_cap', u.amount_cap, 'amount_used', u.amount_used,
                                           'is_warning', u.is_warning, 'is_blocked', u.is_blocked),
               'sessions', coalesce((SELECT sum(rl.cap_units)::int FROM ops.report_lines rl WHERE rl.report_id = r.report_id), 0),
               'amount', coalesce((SELECT sum(rl.line_amount) FROM ops.report_lines rl WHERE rl.report_id = r.report_id), 0),
               'lines', coalesce((
                    SELECT jsonb_agg(jsonb_build_object('date', rl.visit_date,
                                                        'double', stp.code = 'DOUBLE',
                                                        'amount', rl.line_amount,
                                                        'flagged', rl.is_holiday_flag)
                                     ORDER BY rl.visit_date)
                      FROM ops.report_lines rl
                      JOIN ref.session_types stp ON stp.session_type_id = rl.session_type_id
                     WHERE rl.report_id = r.report_id), '[]'::jsonb),
               'approvals', coalesce((
                    SELECT jsonb_agg(jsonb_build_object('decision', a.decision,
                                                        'decided_at', a.decided_at,
                                                        'teacher_name', t.full_name,
                                                        'reason', rr.name_he,
                                                        'comment', a.comment,
                                                        'content_matches', a.content_hash = v_hash)
                                     ORDER BY a.decided_at DESC, a.teacher_approval_id DESC)
                      FROM ops.teacher_approvals a
                      JOIN core.teachers t ON t.teacher_id = a.teacher_id
                      LEFT JOIN ref.rejection_reasons rr ON rr.rejection_reason_id = a.rejection_reason_id
                     WHERE a.report_id = r.report_id), '[]'::jsonb),
               'history', coalesce((
                    SELECT jsonb_agg(jsonb_build_object(
                               'at', h.changed_at,
                               'from', fs.name_he,
                               'to', ts.name_he,
                               'actor_type', h.actor_type,
                               'actor_name', CASE h.actor_type
                                                 WHEN 'SUPPLIER_CONTACT' THEN (SELECT c.full_name FROM core.supplier_contacts c WHERE c.contact_id = h.actor_id)
                                                 WHEN 'TEACHER' THEN (SELECT t.full_name FROM core.teachers t WHERE t.teacher_id = h.actor_id)
                                                 WHEN 'STAFF' THEN (SELECT su.full_name FROM core.staff_users su WHERE su.staff_user_id = h.actor_id)
                                             END,
                               'reason', rr.name_he,
                               'comment', h.comment)
                           ORDER BY h.changed_at DESC, h.history_id DESC)
                      FROM ops.report_status_history h
                      LEFT JOIN ref.report_statuses fs ON fs.status_id = h.from_status_id
                      JOIN ref.report_statuses ts      ON ts.status_id = h.to_status_id
                      LEFT JOIN ref.rejection_reasons rr ON rr.rejection_reason_id = h.rejection_reason_id
                     WHERE h.report_id = r.report_id), '[]'::jsonb)
           )
      INTO v_report
      FROM ops.reports r
      JOIN core.engagements e      ON e.engagement_id = r.engagement_id
      JOIN core.vw_engagement_usage u ON u.engagement_id = e.engagement_id
      JOIN core.kindergartens k    ON k.kindergarten_id = e.kindergarten_id
      JOIN core.suppliers s        ON s.supplier_id = e.supplier_id
      JOIN ref.activity_domains d  ON d.domain_id = e.domain_id
      JOIN ref.engagement_types et ON et.engagement_type_id = e.engagement_type_id
      JOIN ref.report_statuses st  ON st.status_id = r.status_id
      LEFT JOIN core.supplier_contacts sc ON sc.contact_id = r.submitted_by_contact_id
      LEFT JOIN core.staff_users fa       ON fa.staff_user_id = r.final_approved_by_staff_user_id
     WHERE r.report_id = p_report_id
       AND st.code <> 'DRAFT';

    IF v_report IS NULL THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    RETURN jsonb_build_object(
        'staff', to_jsonb(v_staff),
        'reasons', coalesce((
            SELECT jsonb_agg(jsonb_build_object('id', rr.rejection_reason_id, 'name', rr.name_he)
                             ORDER BY rr.rejection_reason_id)
              FROM ref.rejection_reasons rr
             WHERE rr.applies_to = 'STAFF' AND rr.is_active), '[]'::jsonb),
        'report', v_report
    );
END $function$;

-- ---------------------------------------------------------------------
-- 4. אישור סופי ונעילה, או החזרה לספק
--    p_decision: 'APPROVE' | 'RETURN'
--    אישור: רק כשאישור הגננת האחרון הוא "אושר" ותוכן הדיווח לא השתנה מאז.
--           הסטטוס עובר ישר ל"אושר ונעול", והטריגר מכניס אותו לתור של פרוסי.
--    החזרה: דורשת סיבת צוות. בסיבה "אחר" חובה הערה. הספק רואה אותן ויכול לתקן.
--    מחזירה {"ok": true, "status"} או {"ok": false, "message"}.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.staff_decide(
    p_auth_user_id uuid,
    p_report_id    integer,
    p_decision     text,
    p_reason_id    smallint,
    p_comment      text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO ''
AS $function$
DECLARE
    v_staff       record;
    v_comment     text := nullif(btrim(coalesce(p_comment, '')), '');
    v_reason_name text;
    v_rep         record;
    v_last        record;
    v_new         smallint;
    v_new_code    text;
BEGIN
    SELECT * INTO v_staff FROM ops.staff_member(p_auth_user_id);
    IF v_staff.staff_user_id IS NULL OR NOT v_staff.can_act THEN
        RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.actor', 'STAFF:' || v_staff.staff_user_id, true);

    IF p_decision IS NULL OR p_decision NOT IN ('APPROVE', 'RETURN')
       OR p_report_id IS NULL OR length(coalesce(v_comment, '')) > 450 THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    IF p_decision = 'RETURN' THEN
        SELECT rr.name_he INTO v_reason_name
          FROM ref.rejection_reasons rr
         WHERE rr.rejection_reason_id = p_reason_id AND rr.applies_to = 'STAFF' AND rr.is_active;
        IF v_reason_name IS NULL THEN
            RETURN jsonb_build_object('ok', false, 'message', 'יש לבחור את הסיבה להחזרת הדיווח.');
        END IF;
        IF v_reason_name = 'אחר' AND v_comment IS NULL THEN
            RETURN jsonb_build_object('ok', false, 'message', 'כשבוחרים "אחר" יש לכתוב לספק מה צריך לתקן.');
        END IF;
    ELSE
        v_comment := NULL;
    END IF;

    SELECT r.report_id, r.status_id, st.code, st.name_he
      INTO v_rep
      FROM ops.reports r
      JOIN ref.report_statuses st ON st.status_id = r.status_id
     WHERE r.report_id = p_report_id
       FOR UPDATE OF r;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    IF v_rep.code <> 'TEACHER_APPROVED' THEN
        RETURN jsonb_build_object('ok', false,
            'message', 'אפשר לטפל כאן רק בדיווח שהגננת אישרה. הסטטוס עכשיו: ' || v_rep.name_he || '.');
    END IF;

    IF p_decision = 'APPROVE' THEN
        SELECT a.decision, a.content_hash = ops.report_content_hash(p_report_id) AS content_matches
          INTO v_last
          FROM ops.teacher_approvals a
         WHERE a.report_id = p_report_id
         ORDER BY a.decided_at DESC, a.teacher_approval_id DESC
         LIMIT 1;
        IF v_last.decision IS DISTINCT FROM 'APPROVED' OR NOT coalesce(v_last.content_matches, false) THEN
            RETURN jsonb_build_object('ok', false,
                'message', 'תוכן הדיווח לא תואם למה שהגננת אישרה. אין לנעול אותו. יש להחזיר אותו לספק.');
        END IF;
        v_new_code := 'LOCKED';
    ELSE
        v_new_code := 'RETURNED';
    END IF;

    SELECT status_id INTO v_new FROM ref.report_statuses WHERE code = v_new_code;

    IF p_decision = 'APPROVE' THEN
        UPDATE ops.reports
           SET status_id = v_new,
               final_approved_by_staff_user_id = v_staff.staff_user_id,
               final_approved_at = now(),
               locked_at = now()
         WHERE report_id = p_report_id;
    ELSE
        UPDATE ops.reports SET status_id = v_new WHERE report_id = p_report_id;
    END IF;

    INSERT INTO ops.report_status_history (report_id, from_status_id, to_status_id, actor_type, actor_id,
                                           rejection_reason_id, comment)
    VALUES (p_report_id, v_rep.status_id, v_new, 'STAFF', v_staff.staff_user_id,
            CASE WHEN p_decision = 'RETURN' THEN p_reason_id END, v_comment);

    RETURN jsonb_build_object('ok', true, 'status', v_new_code);
END $function$;

-- ---------------------------------------------------------------------
-- 5. תקרות: התקשרויות שקרובות לתקרה או הגיעו אליה
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.staff_caps(p_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
    v_staff record;
BEGIN
    SELECT * INTO v_staff FROM ops.staff_member(p_auth_user_id);
    IF v_staff.staff_user_id IS NULL THEN
        RAISE EXCEPTION 'not staff' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'staff', to_jsonb(v_staff),
        'engagements', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                       'engagement_id', e.engagement_id,
                       'supplier', jsonb_build_object('supplier_id', s.supplier_id, 'number', s.supplier_number, 'name', s.name),
                       'kindergarten', jsonb_build_object('kindergarten_id', k.kindergarten_id,
                                                          'code', k.kindergarten_code,
                                                          'name', k.name,
                                                          'is_mine', k.referent_staff_user_id = v_staff.staff_user_id),
                       'domain', d.name_he,
                       'engagement_type', et.name_he,
                       'tariff', e.tariff_per_session,
                       'session_cap', u.session_cap,
                       'sessions_used', u.sessions_used,
                       'amount_cap', u.amount_cap,
                       'amount_used', u.amount_used,
                       'is_warning', u.is_warning,
                       'is_blocked', u.is_blocked,
                       'overrides', coalesce((
                            SELECT jsonb_agg(jsonb_build_object('extra_sessions', o.extra_sessions,
                                                                'extra_amount', o.extra_amount,
                                                                'reason', o.reason,
                                                                'approved_at', o.approved_at,
                                                                'approved_by', su.full_name)
                                             ORDER BY o.approved_at DESC, o.cap_override_id DESC)
                              FROM core.cap_overrides o
                              LEFT JOIN core.staff_users su ON su.staff_user_id = o.approved_by_staff_user_id
                             WHERE o.engagement_id = e.engagement_id), '[]'::jsonb))
                   ORDER BY u.is_blocked DESC, u.sessions_remaining, s.name, k.name)
              FROM core.engagements e
              JOIN core.vw_engagement_usage u ON u.engagement_id = e.engagement_id
              JOIN core.kindergartens k    ON k.kindergarten_id = e.kindergarten_id
              JOIN core.suppliers s        ON s.supplier_id = e.supplier_id
              JOIN ref.activity_domains d  ON d.domain_id = e.domain_id
              JOIN ref.engagement_types et ON et.engagement_type_id = e.engagement_type_id
             WHERE e.is_active
               AND (u.is_warning OR u.is_blocked)), '[]'::jsonb)
    );
END $function$;

-- ---------------------------------------------------------------------
-- 6. אישור חריגה מתקרה
--    מספר מפגשים נוספים (0 עד 100) וסכום נוסף (0 עד 100,000), לפחות אחד מהם
--    גדול מאפס, וסיבה חובה. מחזירה {"ok": true} או {"ok": false, "message"}.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.staff_add_cap_override(
    p_auth_user_id   uuid,
    p_engagement_id  integer,
    p_extra_sessions smallint,
    p_extra_amount   numeric,
    p_reason         text)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO ''
AS $function$
DECLARE
    v_staff  record;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
    SELECT * INTO v_staff FROM ops.staff_member(p_auth_user_id);
    IF v_staff.staff_user_id IS NULL OR NOT v_staff.can_act THEN
        RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.actor', 'STAFF:' || v_staff.staff_user_id, true);

    IF p_engagement_id IS NULL
       OR coalesce(p_extra_sessions, 0) NOT BETWEEN 0 AND 100
       OR coalesce(p_extra_amount, 0) NOT BETWEEN 0 AND 100000
       OR length(coalesce(v_reason, '')) > 450 THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    IF coalesce(p_extra_sessions, 0) = 0 AND coalesce(p_extra_amount, 0) = 0 THEN
        RETURN jsonb_build_object('ok', false, 'message', 'יש להוסיף לפחות מפגש אחד או סכום.');
    END IF;
    IF v_reason IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'message', 'יש לכתוב את הסיבה לחריגה.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM core.engagements e WHERE e.engagement_id = p_engagement_id AND e.is_active) THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    INSERT INTO core.cap_overrides (engagement_id, extra_sessions, extra_amount, reason, approved_by_staff_user_id, approved_at)
    VALUES (p_engagement_id, nullif(p_extra_sessions, 0), nullif(round(p_extra_amount, 2), 0), v_reason,
            v_staff.staff_user_id, now());

    RETURN jsonb_build_object('ok', true);
END $function$;

-- ---------------------------------------------------------------------
-- 7. הרשאות: רק צד השרת
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION ops.staff_member(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION access.staff_reports(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION access.staff_report(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION access.staff_decide(uuid, integer, text, smallint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION access.staff_caps(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION access.staff_add_cap_override(uuid, integer, smallint, numeric, text) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION ops.staff_member(uuid) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION access.staff_reports(uuid) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION access.staff_report(uuid, integer) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION access.staff_decide(uuid, integer, text, smallint, text) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION access.staff_caps(uuid) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION access.staff_add_cap_override(uuid, integer, smallint, numeric, text) FROM anon, authenticated;
        GRANT EXECUTE ON FUNCTION ops.staff_member(uuid) TO service_role;
        GRANT EXECUTE ON FUNCTION access.staff_reports(uuid) TO service_role;
        GRANT EXECUTE ON FUNCTION access.staff_report(uuid, integer) TO service_role;
        GRANT EXECUTE ON FUNCTION access.staff_decide(uuid, integer, text, smallint, text) TO service_role;
        GRANT EXECUTE ON FUNCTION access.staff_caps(uuid) TO service_role;
        GRANT EXECUTE ON FUNCTION access.staff_add_cap_override(uuid, integer, smallint, numeric, text) TO service_role;
    END IF;
END $$;

COMMIT;
