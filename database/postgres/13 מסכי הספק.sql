/* =====================================================================
   13_supplier_screens.sql  |  PostgreSQL (Supabase)
   פונקציות השרת למסכי הספק באפליקציה
   ---------------------------------------------------------------------
   access.supplier_data(auth_user_id)
       כל מה שמסכי הספק מציגים: הספק, ההתקשרויות עם ניצול התקרות,
       והדיווחים עם שורות התאריכים. רק של הספק המחובר.
   access.supplier_submit(auth_user_id, items)
       שליחת דיווח לגננות. בודקת הכל קודם, ורק אם אין שגיאות כותבת,
       בטרנזקציה אחת. דיווח אחד לכל התקשרות וחודש.

   הספק מזוהה רק לפי auth_user_id שהשרת לוקח מהסשן, אף פעם לא לפי מזהה
   שהדפדפן שולח. רק service_role (צד השרת) יכול להריץ את הפונקציות.

   כללי הדיווח (כמו בדמו):
   * תאריכים מ-3 חודשים אחורה ועד היום (שעון ישראל), בתוך שנת הלימודים של ההתקשרות.
   * מפגש כפול = תעריף כפול, ונספר כמפגש אחד בתקרה (ref.session_types).
   * לא עוברים את התקרה (מפגשים או כסף, כולל חריגות שאושרו). מעבר = פנייה לרפרנטית.
   * גן במסלול ידני, או התקשרות שדורשת אישור מפקחת שלא תועד, לא מדווחים כאן.
   * חודש שכבר נשלח ועוד לא הוחזר לא נשלח שוב. חודש שהוחזר לתיקון (או נדחה)
     נשלח מחדש: רשימת התאריכים החדשה מחליפה את הקודמת באותו דיווח.
   * ביקור בשבת או בחג מסומן ב-is_holiday_flag לבדיקת הרפרנטית.

   להריץ אחרי 07 (הסכמה access חשופה ב-Data API). אפשר להריץ שוב בלי נזק.
   ===================================================================== */

BEGIN;

-- ---------------------------------------------------------------------
-- 1. הנתונים של מסכי הספק
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.supplier_data(p_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
    v_contact_id   integer;
    v_contact_name text;
    v_supplier_id  integer;
    v_today        date := (now() AT TIME ZONE 'Asia/Jerusalem')::date;
    v_min          date := ((now() AT TIME ZONE 'Asia/Jerusalem')::date - interval '3 months')::date;
BEGIN
    SELECT c.contact_id, c.full_name, c.supplier_id
      INTO v_contact_id, v_contact_name, v_supplier_id
      FROM core.supplier_contacts c
      JOIN core.suppliers s ON s.supplier_id = c.supplier_id
     WHERE c.auth_user_id = p_auth_user_id
       AND c.is_active AND c.can_login AND s.is_active
     ORDER BY c.contact_id
     LIMIT 1;

    IF v_contact_id IS NULL THEN
        RAISE EXCEPTION 'not a supplier contact' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'supplier', (SELECT jsonb_build_object('supplier_id', s.supplier_id,
                                               'name', s.name,
                                               'supplier_number', s.supplier_number)
                       FROM core.suppliers s WHERE s.supplier_id = v_supplier_id),
        'contact',  jsonb_build_object('contact_id', v_contact_id, 'full_name', v_contact_name),
        'today',    v_today,
        'min_date', v_min,
        'holidays', coalesce((SELECT jsonb_agg(jsonb_build_object('date', h.holiday_date, 'name', h.name_he)
                                               ORDER BY h.holiday_date)
                                FROM ref.holidays h
                               WHERE h.holiday_date BETWEEN v_min AND v_today), '[]'::jsonb),

        -- התקשרויות שאפשר לדווח עליהן בתקופה הנוכחית, עם ניצול התקרות
        'engagements', coalesce((
            SELECT jsonb_agg(x.j ORDER BY x.kg_name, x.engagement_id)
              FROM (SELECT k.name AS kg_name, e.engagement_id,
                           jsonb_build_object(
                               'engagement_id', e.engagement_id,
                               'kindergarten', jsonb_build_object(
                                   'kindergarten_id', k.kindergarten_id,
                                   'code', k.kindergarten_code,
                                   'name', k.name,
                                   'is_manual_track', k.is_manual_track),
                               'teachers', coalesce((
                                   SELECT jsonb_agg(t.full_name ORDER BY a.is_substitute, t.full_name)
                                     FROM core.teacher_assignments a
                                     JOIN core.teachers t ON t.teacher_id = a.teacher_id
                                    WHERE a.kindergarten_id = k.kindergarten_id
                                      AND t.is_active
                                      AND a.valid_from <= v_today
                                      AND (a.valid_to IS NULL OR a.valid_to >= v_today)), '[]'::jsonb),
                               'domain', d.name_he,
                               'engagement_type', et.name_he,
                               'school_year', jsonb_build_object('id', y.school_year_id, 'name', y.hebrew_name,
                                                                 'start', y.start_date, 'end', y.end_date),
                               'tariff', e.tariff_per_session,
                               'session_cap', u.session_cap,
                               'amount_cap', u.amount_cap,
                               'sessions_used', u.sessions_used,
                               'amount_used', u.amount_used,
                               'is_warning', u.is_warning,
                               'is_blocked', u.is_blocked,
                               'block_reason', CASE
                                   WHEN k.is_manual_track THEN 'MANUAL_TRACK'
                                   WHEN et.requires_supervisor_approval AND e.supervisor_approval_id IS NULL
                                        THEN 'NEEDS_SUPERVISOR_APPROVAL'
                                   ELSE NULL END
                           ) AS j
                      FROM core.engagements e
                      JOIN core.kindergartens k     ON k.kindergarten_id = e.kindergarten_id
                      JOIN ref.activity_domains d   ON d.domain_id = e.domain_id
                      JOIN ref.engagement_types et  ON et.engagement_type_id = e.engagement_type_id
                      JOIN ref.school_years y       ON y.school_year_id = e.school_year_id
                      JOIN core.vw_engagement_usage u ON u.engagement_id = e.engagement_id
                     WHERE e.supplier_id = v_supplier_id
                       AND e.is_active AND k.is_active
                       AND y.end_date >= v_min
                       AND y.start_date <= v_today) x), '[]'::jsonb),

        -- כל הדיווחים של הספק, החדשים קודם
        'reports', coalesce((
            SELECT jsonb_agg(x.j ORDER BY x.report_year DESC, x.report_month DESC, x.kg_name, x.report_id)
              FROM (SELECT r.report_year, r.report_month, r.report_id, k.name AS kg_name,
                           jsonb_build_object(
                               'report_id', r.report_id,
                               'engagement_id', r.engagement_id,
                               'year', r.report_year,
                               'month', r.report_month,
                               'status', st.code,
                               'status_name', st.name_he,
                               'editable', st.code IN ('DRAFT', 'RETURNED', 'TEACHER_REJECTED'),
                               'is_manual', r.is_manual,
                               'submitted_at', r.submitted_at,
                               'updated_at', r.updated_at,
                               'kindergarten', jsonb_build_object('code', k.kindergarten_code, 'name', k.name),
                               'domain', d.name_he,
                               'sessions', coalesce(l.sessions, 0),
                               'amount', coalesce(l.amount, 0),
                               'lines', coalesce(l.lines, '[]'::jsonb),
                               'note', n.note
                           ) AS j
                      FROM ops.reports r
                      JOIN core.engagements e     ON e.engagement_id = r.engagement_id
                      JOIN core.kindergartens k   ON k.kindergarten_id = e.kindergarten_id
                      JOIN ref.activity_domains d ON d.domain_id = e.domain_id
                      JOIN ref.report_statuses st ON st.status_id = r.status_id
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
                      LEFT JOIN LATERAL (   -- ההערה האחרונה של מי שהחזיר את הדיווח לתיקון
                           SELECT jsonb_build_object('comment', h.comment,
                                                     'reason', rr.name_he,
                                                     'by', h.actor_type,
                                                     'at', h.changed_at) AS note
                             FROM ops.report_status_history h
                             JOIN ref.report_statuses s2 ON s2.status_id = h.to_status_id
                             LEFT JOIN ref.rejection_reasons rr ON rr.rejection_reason_id = h.rejection_reason_id
                            WHERE h.report_id = r.report_id
                              AND s2.code IN ('RETURNED', 'TEACHER_REJECTED')
                            ORDER BY h.changed_at DESC, h.history_id DESC
                            LIMIT 1) n ON true
                     WHERE e.supplier_id = v_supplier_id) x), '[]'::jsonb)
    );
END $function$;


-- ---------------------------------------------------------------------
-- 2. שליחת דיווח לגננות
--    p_items: [{"engagement_id": 2, "lines": [{"date": "2026-11-03", "double": false}, ...]}, ...]
--    מחזירה {"ok": true, "reports": [...]} או {"ok": false, "errors": [{"engagement_id", "message"}]}
--    קלט במבנה לא תקין, או התקשרות שאינה של הספק, עוצרים עם שגיאה כללית.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION access.supplier_submit(p_auth_user_id uuid, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO ''
AS $function$
DECLARE
    v_contact_id  integer;
    v_supplier_id integer;
    v_today       date := (now() AT TIME ZONE 'Asia/Jerusalem')::date;
    v_min         date := ((now() AT TIME ZONE 'Asia/Jerusalem')::date - interval '3 months')::date;
    v_months      text[] := ARRAY['ינואר','פברואר','מרץ','אפריל','מאי','יוני',
                                  'יולי','אוגוסט','ספטמבר','אוקטובר','נובמבר','דצמבר'];
    v_regular     smallint;
    v_double      smallint;
    v_sent        smallint;
    v_rows        jsonb;
    v_item        jsonb;
    v_line        jsonb;
    v_eng         record;
    v_grp         record;
    v_errors      jsonb := '[]'::jsonb;
    v_done        jsonb := '[]'::jsonb;
    v_n_items     integer;
    v_n_engs      integer;
    v_from        date;
    v_to          date;
    v_bad         integer;
    v_used_s      integer;
    v_used_m      numeric;
    v_extra_s     integer;
    v_extra_m     numeric;
    v_new_s       integer;
    v_new_m       numeric;
    v_report_id   integer;
    v_prev_status smallint;
BEGIN
    -- מי הספק: רק לפי הסשן בשרת
    SELECT c.contact_id, c.supplier_id
      INTO v_contact_id, v_supplier_id
      FROM core.supplier_contacts c
      JOIN core.suppliers s ON s.supplier_id = c.supplier_id
     WHERE c.auth_user_id = p_auth_user_id
       AND c.is_active AND c.can_login AND s.is_active
     ORDER BY c.contact_id
     LIMIT 1;

    IF v_contact_id IS NULL THEN
        RAISE EXCEPTION 'not a supplier contact' USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.actor', 'SUPPLIER_CONTACT:' || v_contact_id, true);

    -- מבנה הקלט
    IF jsonb_typeof(p_items) IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 50 THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
        IF jsonb_typeof(v_item) IS DISTINCT FROM 'object'
           OR coalesce(v_item->>'engagement_id', '') !~ '^[0-9]{1,9}$'
           OR jsonb_typeof(v_item->'lines') IS DISTINCT FROM 'array'
           OR jsonb_array_length(v_item->'lines') NOT BETWEEN 1 AND 62 THEN
            RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
        END IF;
        FOR v_line IN SELECT value FROM jsonb_array_elements(v_item->'lines') LOOP
            IF jsonb_typeof(v_line) IS DISTINCT FROM 'object'
               OR coalesce(v_line->>'date', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
               OR jsonb_typeof(v_line->'double') IS DISTINCT FROM 'boolean' THEN
                RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
            END IF;
        END LOOP;
    END LOOP;

    -- כל השורות כרשימה אחת (תאריך לא קיים, כמו 31.2, נכשל כאן)
    SELECT jsonb_agg(jsonb_build_object('engagement_id', (i.value->>'engagement_id')::int,
                                        'visit_date',    (l.value->>'date')::date,
                                        'is_double',     (l.value->>'double')::boolean))
      INTO v_rows
      FROM jsonb_array_elements(p_items) i
     CROSS JOIN LATERAL jsonb_array_elements(i.value->'lines') l;

    -- כל התקשרות פעם אחת, וכל תאריך פעם אחת בהתקשרות
    SELECT count(*), count(DISTINCT value->>'engagement_id')
      INTO v_n_items, v_n_engs
      FROM jsonb_array_elements(p_items);
    IF v_n_items <> v_n_engs OR EXISTS (
        SELECT 1 FROM jsonb_to_recordset(v_rows) x(engagement_id int, visit_date date, is_double boolean)
         GROUP BY x.engagement_id, x.visit_date HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    -- כל ההתקשרויות שייכות לספק הזה
    SELECT count(*) INTO v_bad
      FROM core.engagements e
     WHERE e.supplier_id = v_supplier_id
       AND e.engagement_id IN (SELECT (value->>'engagement_id')::int FROM jsonb_array_elements(p_items));
    IF v_bad <> v_n_engs THEN
        RAISE EXCEPTION 'invalid input' USING ERRCODE = '22023';
    END IF;

    SELECT session_type_id INTO v_regular FROM ref.session_types   WHERE code = 'REGULAR';
    SELECT session_type_id INTO v_double  FROM ref.session_types   WHERE code = 'DOUBLE';
    SELECT status_id       INTO v_sent    FROM ref.report_statuses WHERE code = 'SENT_TO_TEACHER';

    -- בדיקות לכל התקשרות. נעילת השורות מונעת שתי שליחות במקביל שעוברות יחד את התקרה
    FOR v_eng IN
        SELECT e.engagement_id, e.tariff_per_session, e.max_sessions, e.annual_budget,
               e.supervisor_approval_id, e.is_active, et.requires_supervisor_approval,
               k.name AS kg_name, k.is_manual_track, k.is_active AS kg_active,
               y.start_date, y.end_date
          FROM core.engagements e
          JOIN core.kindergartens k    ON k.kindergarten_id = e.kindergarten_id
          JOIN ref.engagement_types et ON et.engagement_type_id = e.engagement_type_id
          JOIN ref.school_years y      ON y.school_year_id = e.school_year_id
         WHERE e.supplier_id = v_supplier_id
           AND e.engagement_id IN (SELECT (value->>'engagement_id')::int FROM jsonb_array_elements(p_items))
         ORDER BY e.engagement_id
           FOR UPDATE OF e
    LOOP
        IF NOT v_eng.is_active OR NOT v_eng.kg_active THEN
            v_errors := v_errors || jsonb_build_object('engagement_id', v_eng.engagement_id,
                'message', 'ההתקשרות ב' || v_eng.kg_name || ' אינה פעילה.');
            CONTINUE;
        END IF;
        IF v_eng.is_manual_track THEN
            v_errors := v_errors || jsonb_build_object('engagement_id', v_eng.engagement_id,
                'message', v_eng.kg_name || ' במסלול טופס ידני. את הדיווח מגישים בטופס הנייר החתום.');
            CONTINUE;
        END IF;
        IF v_eng.requires_supervisor_approval AND v_eng.supervisor_approval_id IS NULL THEN
            v_errors := v_errors || jsonb_build_object('engagement_id', v_eng.engagement_id,
                'message', 'ההתקשרות ב' || v_eng.kg_name || ' ממתינה לאישור מפקחת. אי אפשר לדווח עליה עדיין.');
            CONTINUE;
        END IF;

        -- טווח התאריכים
        v_from := greatest(v_min, v_eng.start_date);
        v_to   := least(v_today, v_eng.end_date);
        SELECT count(*) INTO v_bad
          FROM jsonb_to_recordset(v_rows) x(engagement_id int, visit_date date, is_double boolean)
         WHERE x.engagement_id = v_eng.engagement_id
           AND (x.visit_date < v_from OR x.visit_date > v_to);
        IF v_bad > 0 THEN
            v_errors := v_errors || jsonb_build_object('engagement_id', v_eng.engagement_id,
                'message', 'ב' || v_eng.kg_name || ' אפשר לדווח רק על תאריכים מ-'
                           || to_char(v_from, 'DD.MM.YYYY') || ' עד ' || to_char(v_to, 'DD.MM.YYYY') || '.');
            CONTINUE;
        END IF;

        -- חודש שכבר נשלח ולא הוחזר לתיקון
        FOR v_grp IN
            SELECT DISTINCT r.report_year, r.report_month, st.name_he
              FROM jsonb_to_recordset(v_rows) x(engagement_id int, visit_date date, is_double boolean)
              JOIN ops.reports r ON r.engagement_id = x.engagement_id
                                AND r.report_year  = extract(year  FROM x.visit_date)
                                AND r.report_month = extract(month FROM x.visit_date)
              JOIN ref.report_statuses st ON st.status_id = r.status_id
             WHERE x.engagement_id = v_eng.engagement_id
               AND st.code NOT IN ('DRAFT', 'RETURNED', 'TEACHER_REJECTED')
             ORDER BY 1, 2
        LOOP
            v_errors := v_errors || jsonb_build_object('engagement_id', v_eng.engagement_id,
                'message', 'הדיווח על ' || v_months[v_grp.report_month] || ' ' || v_grp.report_year
                           || ' ב' || v_eng.kg_name || ' כבר נשלח (' || v_grp.name_he
                           || '). אפשר לשלוח אותו שוב רק אם הוא יוחזר לתיקון.');
        END LOOP;

        -- תקרות: מה שכבר דווח (בלי דיווחים שנדחו ובלי החודשים שמוחלפים עכשיו) ועוד מה שנשלח עכשיו
        SELECT coalesce(sum(l.cap_units), 0), coalesce(sum(l.line_amount), 0)
          INTO v_used_s, v_used_m
          FROM ops.reports r
          JOIN ops.report_lines l     ON l.report_id = r.report_id
          JOIN ref.report_statuses st ON st.status_id = r.status_id
         WHERE r.engagement_id = v_eng.engagement_id
           AND st.code <> 'TEACHER_REJECTED'
           AND NOT EXISTS (
               SELECT 1 FROM jsonb_to_recordset(v_rows) x(engagement_id int, visit_date date, is_double boolean)
                WHERE x.engagement_id = r.engagement_id
                  AND extract(year  FROM x.visit_date) = r.report_year
                  AND extract(month FROM x.visit_date) = r.report_month);

        SELECT coalesce(sum(o.extra_sessions), 0), coalesce(sum(o.extra_amount), 0)
          INTO v_extra_s, v_extra_m
          FROM core.cap_overrides o
         WHERE o.engagement_id = v_eng.engagement_id;

        SELECT coalesce(sum(st.cap_units), 0), coalesce(sum(round(v_eng.tariff_per_session * st.pay_multiplier, 2)), 0)
          INTO v_new_s, v_new_m
          FROM jsonb_to_recordset(v_rows) x(engagement_id int, visit_date date, is_double boolean)
          JOIN ref.session_types st ON st.session_type_id = CASE WHEN x.is_double THEN v_double ELSE v_regular END
         WHERE x.engagement_id = v_eng.engagement_id;

        IF v_used_s + v_new_s > v_eng.max_sessions + v_extra_s
           OR v_used_m + v_new_m > v_eng.annual_budget + v_extra_m THEN
            v_errors := v_errors || jsonb_build_object('engagement_id', v_eng.engagement_id,
                'message', 'הדיווח ב' || v_eng.kg_name || ' עובר את תקרת ההתקשרות. נותרו '
                           || greatest(v_eng.max_sessions + v_extra_s - v_used_s, 0) || ' מפגשים ו-₪'
                           || to_char(greatest(v_eng.annual_budget + v_extra_m - v_used_m, 0), 'FM999,999,990')
                           || '. לאישור חריגה יש לפנות לרפרנטית.');
        END IF;
    END LOOP;

    IF jsonb_array_length(v_errors) > 0 THEN
        RETURN jsonb_build_object('ok', false, 'errors', v_errors);
    END IF;

    -- כתיבה: דיווח אחד לכל התקשרות וחודש
    FOR v_grp IN
        SELECT x.engagement_id,
               extract(year  FROM x.visit_date)::smallint AS y,
               extract(month FROM x.visit_date)::smallint AS m
          FROM jsonb_to_recordset(v_rows) x(engagement_id int, visit_date date, is_double boolean)
         GROUP BY 1, 2, 3
         ORDER BY 1, 2, 3
    LOOP
        v_report_id := NULL;
        v_prev_status := NULL;

        SELECT r.report_id, r.status_id
          INTO v_report_id, v_prev_status
          FROM ops.reports r
         WHERE r.engagement_id = v_grp.engagement_id
           AND r.report_year = v_grp.y AND r.report_month = v_grp.m
           FOR UPDATE;

        IF v_report_id IS NULL THEN
            INSERT INTO ops.reports (engagement_id, report_year, report_month, status_id,
                                     submitted_by_contact_id, submitted_at)
            VALUES (v_grp.engagement_id, v_grp.y, v_grp.m, v_sent, v_contact_id, now())
            RETURNING report_id INTO v_report_id;
        ELSE
            -- דיווח שהוחזר לתיקון: תאריכים שהוסרו יוצאים מהדיווח
            DELETE FROM ops.report_lines rl
             WHERE rl.report_id = v_report_id
               AND rl.visit_date NOT IN (
                   SELECT x.visit_date
                     FROM jsonb_to_recordset(v_rows) x(engagement_id int, visit_date date, is_double boolean)
                    WHERE x.engagement_id = v_grp.engagement_id);

            UPDATE ops.reports
               SET status_id = v_sent,
                   submitted_by_contact_id = v_contact_id,
                   submitted_at = now(),
                   updated_at = now()
             WHERE report_id = v_report_id;
        END IF;

        INSERT INTO ops.report_lines (report_id, engagement_id, visit_date, session_type_id,
                                      tariff_applied, pay_multiplier, cap_units, is_holiday_flag)
        SELECT v_report_id, x.engagement_id, x.visit_date, st.session_type_id,
               e.tariff_per_session, st.pay_multiplier, st.cap_units,
               extract(isodow FROM x.visit_date) = 6
                 OR EXISTS (SELECT 1 FROM ref.holidays h WHERE h.holiday_date = x.visit_date)
          FROM jsonb_to_recordset(v_rows) x(engagement_id int, visit_date date, is_double boolean)
          JOIN core.engagements e   ON e.engagement_id = x.engagement_id
          JOIN ref.session_types st ON st.session_type_id = CASE WHEN x.is_double THEN v_double ELSE v_regular END
         WHERE x.engagement_id = v_grp.engagement_id
           AND extract(year  FROM x.visit_date) = v_grp.y
           AND extract(month FROM x.visit_date) = v_grp.m
        ON CONFLICT (engagement_id, visit_date) DO UPDATE
           SET session_type_id = EXCLUDED.session_type_id,
               tariff_applied  = EXCLUDED.tariff_applied,
               pay_multiplier  = EXCLUDED.pay_multiplier,
               cap_units       = EXCLUDED.cap_units,
               is_holiday_flag = EXCLUDED.is_holiday_flag;

        INSERT INTO ops.report_status_history (report_id, from_status_id, to_status_id,
                                               actor_type, actor_id, comment)
        VALUES (v_report_id, v_prev_status, v_sent, 'SUPPLIER_CONTACT', v_contact_id,
                CASE WHEN v_prev_status IS NULL THEN NULL ELSE 'נשלח מחדש אחרי תיקון' END);

        v_done := v_done || jsonb_build_object('report_id', v_report_id,
                                               'engagement_id', v_grp.engagement_id,
                                               'year', v_grp.y, 'month', v_grp.m);
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'reports', v_done);
END $function$;


-- ---------------------------------------------------------------------
-- 3. הרשאות: רק service_role (צד השרת)
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION access.supplier_data(uuid)          FROM PUBLIC;
REVOKE ALL ON FUNCTION access.supplier_submit(uuid, jsonb) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION access.supplier_data(uuid)          FROM anon, authenticated;
        REVOKE ALL ON FUNCTION access.supplier_submit(uuid, jsonb) FROM anon, authenticated;
        GRANT EXECUTE ON FUNCTION access.supplier_data(uuid)          TO service_role;
        GRANT EXECUTE ON FUNCTION access.supplier_submit(uuid, jsonb) TO service_role;
    END IF;
END $$;

COMMIT;
