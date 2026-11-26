/* =====================================================================
   17_monthly_report_and_metrics.sql  |  PostgreSQL (Supabase)
   פונקציות השרת לדוח החודשי ולמדדים במסכי הצוות
   ---------------------------------------------------------------------
   access.staff_monthly(auth_user_id, year, month)
       כל הדיווחים של חודש פעילות אחד (בלי טיוטות), עם ימי פעילות, מפגשים
       כפולים, מפגשים וסכום. "לתשלום" = רק דיווחים שאושרו סופית או ננעלו,
       כמו בשאילתה 1 בקובץ 06. גם רשימת החודשים שיש בהם דיווחים, לבחירה.
   access.staff_metrics(auth_user_id)
       מדדים ל-12 חודשי הפעילות האחרונים, כמו שאילתות 4 עד 6 בקובץ 06:
       זמן טיפול (משליחה לאישור הגננת, ומשליחה לאישור הסופי), אחוז דיווחים
       שהוחזרו או נדחו (לפי חודש ולפי ספק), ואחוז אישורים דיגיטליים.

   כל איש צוות פעיל (כולל "צפייה בלבד") רואה. שתי הפונקציות רק קוראות.
   רק service_role (צד השרת) יכול להריץ. להריץ אחרי 16. אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

-- ---------------------------------------------------------------------
-- 1. דוח חודשי
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.staff_monthly(p_auth_user_id uuid, p_year integer, p_month integer)
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

    IF p_year IS NULL OR p_year NOT BETWEEN 2020 AND 2100 OR p_month IS NULL OR p_month NOT BETWEEN 1 AND 12 THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    RETURN jsonb_build_object(
        'staff', to_jsonb(v_staff),
        'year', p_year,
        'month', p_month,
        'months', coalesce((
            SELECT jsonb_agg(jsonb_build_object('year', m.y, 'month', m.m, 'reports', m.n) ORDER BY m.y DESC, m.m DESC)
              FROM (SELECT r.report_year AS y, r.report_month AS m, count(*)::int AS n
                      FROM ops.reports r
                      JOIN ref.report_statuses st ON st.status_id = r.status_id
                     WHERE st.code <> 'DRAFT'
                     GROUP BY r.report_year, r.report_month
                     ORDER BY r.report_year DESC, r.report_month DESC
                     LIMIT 36) m), '[]'::jsonb),
        'reports', coalesce((
            SELECT jsonb_agg(x.j ORDER BY x.supplier_name, x.kg_name, x.report_id)
              FROM (SELECT s.name AS supplier_name, k.name AS kg_name, r.report_id,
                           jsonb_build_object(
                               'report_id', r.report_id,
                               'status', st.code,
                               'status_name', st.name_he,
                               'is_final', st.code IN ('STAFF_APPROVED', 'LOCKED'),
                               'supplier', jsonb_build_object('supplier_id', s.supplier_id,
                                                              'number', s.supplier_number,
                                                              'name', s.name),
                               'kindergarten', jsonb_build_object('kindergarten_id', k.kindergarten_id,
                                                                  'code', k.kindergarten_code,
                                                                  'name', k.name,
                                                                  'is_mine', k.referent_staff_user_id = v_staff.staff_user_id),
                               'domain', d.name_he,
                               'tariff', e.tariff_per_session,
                               'days', coalesce(l.days, 0),
                               'doubles', coalesce(l.doubles, 0),
                               'sessions', coalesce(l.sessions, 0),
                               'amount', coalesce(l.amount, 0),
                               'locked_at', r.locked_at,
                               'final_approved_by', fa.full_name
                           ) AS j
                      FROM ops.reports r
                      JOIN ref.report_statuses st ON st.status_id = r.status_id
                      JOIN core.engagements e     ON e.engagement_id = r.engagement_id
                      JOIN core.suppliers s       ON s.supplier_id = e.supplier_id
                      JOIN core.kindergartens k   ON k.kindergarten_id = e.kindergarten_id
                      JOIN ref.activity_domains d ON d.domain_id = e.domain_id
                      LEFT JOIN core.staff_users fa ON fa.staff_user_id = r.final_approved_by_staff_user_id
                      LEFT JOIN LATERAL (
                           SELECT count(*)::int                                     AS days,
                                  count(*) FILTER (WHERE stp.code = 'DOUBLE')::int  AS doubles,
                                  sum(rl.cap_units)::int                            AS sessions,
                                  sum(rl.line_amount)                               AS amount
                             FROM ops.report_lines rl
                             JOIN ref.session_types stp ON stp.session_type_id = rl.session_type_id
                            WHERE rl.report_id = r.report_id) l ON true
                     WHERE r.report_year = p_year
                       AND r.report_month = p_month
                       AND st.code <> 'DRAFT') x), '[]'::jsonb)
    );
END $function$;

-- ---------------------------------------------------------------------
-- 2. מדדים
--    זמנים בימים קלנדריים, עם ספרה אחת אחרי הנקודה.
--    "הוחזר או נדחו" = דיווח שעבר לפחות פעם אחת ל"נדחה ע"י הגננת" או
--    ל"דורש תיקון", גם אם תוקן מאז. נספר פעם אחת.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.staff_metrics(p_auth_user_id uuid)
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

    v_from := extract(year FROM v_today)::int * 12 + extract(month FROM v_today)::int - 11;

    RETURN jsonb_build_object(
        'staff', to_jsonb(v_staff),
        'today', v_today,
        'months', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                       'year', q.y,
                       'month', q.m,
                       'reports', q.total,
                       'final', q.final,
                       'avg_days_to_final', q.avg_final,
                       'max_days_to_final', q.max_final,
                       'teacher_approved', q.teacher_n,
                       'avg_days_to_teacher', q.avg_teacher,
                       'teacher_within_5_days', q.teacher_5,
                       'approved', q.approved,
                       'digital', q.digital,
                       'bounced', q.bounced)
                   ORDER BY q.y, q.m)
              FROM (SELECT r.report_year AS y, r.report_month AS m,
                           count(*)::int AS total,
                           count(*) FILTER (WHERE r.final_approved_at IS NOT NULL)::int AS final,
                           round(avg(extract(epoch FROM r.final_approved_at - r.submitted_at) / 86400.0)
                                 FILTER (WHERE r.final_approved_at IS NOT NULL AND r.submitted_at IS NOT NULL), 1) AS avg_final,
                           round(max(extract(epoch FROM r.final_approved_at - r.submitted_at) / 86400.0)
                                 FILTER (WHERE r.final_approved_at IS NOT NULL AND r.submitted_at IS NOT NULL), 1) AS max_final,
                           count(ta.decided_at)::int AS teacher_n,
                           round(avg(extract(epoch FROM ta.decided_at - r.submitted_at) / 86400.0), 1) AS avg_teacher,
                           count(*) FILTER (WHERE ta.decided_at - r.submitted_at <= interval '5 days')::int AS teacher_5,
                           count(*) FILTER (WHERE st.code IN ('TEACHER_APPROVED', 'STAFF_APPROVED', 'LOCKED'))::int AS approved,
                           count(*) FILTER (WHERE st.code IN ('TEACHER_APPROVED', 'STAFF_APPROVED', 'LOCKED')
                                              AND NOT r.is_manual)::int AS digital,
                           count(*) FILTER (WHERE EXISTS (
                                SELECT 1 FROM ops.report_status_history h
                                  JOIN ref.report_statuses hs ON hs.status_id = h.to_status_id
                                 WHERE h.report_id = r.report_id
                                   AND hs.code IN ('TEACHER_REJECTED', 'RETURNED')))::int AS bounced
                      FROM ops.reports r
                      JOIN ref.report_statuses st ON st.status_id = r.status_id
                      LEFT JOIN LATERAL (
                           -- The teacher approval of the current submission.
                           SELECT a.decided_at
                             FROM ops.teacher_approvals a
                            WHERE a.report_id = r.report_id
                              AND a.decision = 'APPROVED'
                              AND a.decided_at >= r.submitted_at
                            ORDER BY a.decided_at DESC
                            LIMIT 1) ta ON true
                     WHERE st.code <> 'DRAFT'
                       AND r.report_year * 12 + r.report_month >= v_from
                     GROUP BY r.report_year, r.report_month) q), '[]'::jsonb),
        'suppliers', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                       'supplier_id', q.supplier_id,
                       'number', q.supplier_number,
                       'name', q.name,
                       'reports', q.total,
                       'bounced', q.bounced)
                   ORDER BY q.bounced::numeric / q.total DESC, q.total DESC, q.name)
              FROM (SELECT s.supplier_id, s.supplier_number, s.name,
                           count(*)::int AS total,
                           count(*) FILTER (WHERE EXISTS (
                                SELECT 1 FROM ops.report_status_history h
                                  JOIN ref.report_statuses hs ON hs.status_id = h.to_status_id
                                 WHERE h.report_id = r.report_id
                                   AND hs.code IN ('TEACHER_REJECTED', 'RETURNED')))::int AS bounced
                      FROM ops.reports r
                      JOIN ref.report_statuses st ON st.status_id = r.status_id
                      JOIN core.engagements e     ON e.engagement_id = r.engagement_id
                      JOIN core.suppliers s       ON s.supplier_id = e.supplier_id
                     WHERE st.code <> 'DRAFT'
                       AND r.report_year * 12 + r.report_month >= v_from
                     GROUP BY s.supplier_id, s.supplier_number, s.name) q), '[]'::jsonb)
    );
END $function$;

-- ---------------------------------------------------------------------
-- 3. הרשאות: רק צד השרת
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION access.staff_monthly(uuid, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION access.staff_metrics(uuid) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION access.staff_monthly(uuid, integer, integer) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION access.staff_metrics(uuid) FROM anon, authenticated;
        GRANT EXECUTE ON FUNCTION access.staff_monthly(uuid, integer, integer) TO service_role;
        GRANT EXECUTE ON FUNCTION access.staff_metrics(uuid) TO service_role;
    END IF;
END $$;

COMMIT;
