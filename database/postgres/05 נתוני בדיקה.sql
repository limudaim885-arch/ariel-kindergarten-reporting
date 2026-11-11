/* =====================================================================
   05_test_data.sql  |  שלב א'  |  גרסת PostgreSQL  |  סביבת בדיקות בלבד!
   נתוני דוגמה עם שמות וטלפונים פיקטיביים (050-0000xxx), כדי שאף SMS
   לא יגיע לגננת או לספק אמיתיים בזמן בדיקות.
   להריץ אחרי 01, 02 ו-03. לא להריץ על מסד הייצור.
   ===================================================================== */
BEGIN;

SELECT set_config('app.actor', 'TEST_DATA', true);

DO $$
DECLARE
    v_year     smallint := 2027;   -- תשפ"ז
    v_referent integer;
    v_sup      integer;
    v_sup_appr integer;
    v_e1       integer;
    v_e2       integer;
    v_contact  integer;
    v_r1       integer;
    v_r2       integer;
BEGIN
    IF EXISTS (SELECT 1 FROM core.suppliers WHERE supplier_number NOT LIKE '9001%') THEN
        RAISE EXCEPTION 'נמצאו ספקים שאינם נתוני בדיקה. נראה שזה מסד הייצור, הריצה נעצרה';
    END IF;

    /* צוות */
    INSERT INTO core.staff_users (full_name, email, role_id) VALUES
     ('מנהלת בדיקות', 'admin.test@example.org', 1),
     ('רפרנטית בדיקות', 'referent.test@example.org', 2);
    SELECT staff_user_id INTO v_referent FROM core.staff_users WHERE email = 'referent.test@example.org';

    /* מפקחת */
    INSERT INTO core.supervisors (full_name, email) VALUES ('מפקחת לדוגמה', 'supervisor.test@example.org')
    RETURNING supervisor_id INTO v_sup;

    /* ספקים ואנשי קשר */
    INSERT INTO core.suppliers (supplier_number, name, email) VALUES
     ('900101', 'ריתמיקה לדוגמה', 'rhythm.test@example.org'),
     ('900102', 'תיאטרון לדוגמה', 'theatre.test@example.org'),
     ('900103', 'חוות חיות לדוגמה', NULL);
    INSERT INTO core.supplier_contacts (supplier_id, full_name, mobile_phone, is_primary)
    SELECT s.supplier_id, v.full_name, v.phone, v.is_primary
    FROM (VALUES ('900101', 'נעמה בדיקה',  '0500000101', true),
                 ('900102', 'אביטל בדיקה', '0500000102', true),
                 ('900102', 'אילנית בדיקה', '0500000112', false),   -- ספק עם שני אנשי קשר
                 ('900103', 'גיא בדיקה',   '0500000103', true)) v (supplier_number, full_name, phone, is_primary)
    JOIN core.suppliers s ON s.supplier_number = v.supplier_number;

    /* גנים, גננות ושיבוצים */
    INSERT INTO core.kindergartens (kindergarten_code, name, supervisor_id, referent_staff_user_id, is_manual_track) VALUES
     ('900001', 'גן ארגמן בדיקה', v_sup, v_referent, false),
     ('900002', 'גן תאנה בדיקה',  v_sup, v_referent, false),   -- שתי גננות
     ('900003', 'גן שחר בדיקה',   v_sup, v_referent, true);    -- מסלול ידני
    INSERT INTO core.teachers (full_name, mobile_phone) VALUES
     ('גננת א בדיקה', '0500000201'),
     ('גננת ב בדיקה', '0500000202'),
     ('גננת ג בדיקה', '0500000203'),
     ('גננת ד בדיקה', '0500000204');
    INSERT INTO core.teacher_assignments (teacher_id, kindergarten_id, valid_from, is_substitute)
    SELECT t.teacher_id, k.kindergarten_id, DATE '2026-09-01', v.is_sub
    FROM (VALUES ('0500000201','900001',false), ('0500000202','900002',false),
                 ('0500000203','900002',false), ('0500000204','900003',false)) v (phone, kg, is_sub)
    JOIN core.teachers t      ON t.mobile_phone = v.phone
    JOIN core.kindergartens k ON k.kindergarten_code = v.kg;

    /* אישור מפקחת להתקשרות חד פעמית */
    INSERT INTO core.supervisor_approvals (supervisor_id, approved_on, recorded_by_staff_user_id, notes)
    VALUES (v_sup, '2026-09-20', v_referent, 'אישור הצגת חנוכה, דוגמה')
    RETURNING supervisor_approval_id INTO v_sup_appr;

    /* התקשרויות */
    INSERT INTO core.engagements (school_year_id, supplier_id, kindergarten_id, domain_id, engagement_type_id,
                                  tariff_per_session, max_sessions, annual_budget, supervisor_approval_id)
    SELECT v_year, s.supplier_id, k.kindergarten_id, d.domain_id, v.type_id, v.tariff, v.max_s, v.tariff * v.max_s,
           CASE WHEN v.type_id = 1 THEN NULL ELSE v_sup_appr END
    FROM (VALUES ('900101','900001','ריתמיקה',       1, 250.00, 30),
                 ('900101','900002','ריתמיקה',       1, 250.00,  5),   -- תקרה נמוכה לבדיקת התראה וחסימה
                 ('900102','900001','תיאטרון ודרמה', 2, 900.00,  1),   -- חד פעמי
                 ('900103','900003','חיות וטבע',     1, 260.00, 20)) v (sn, kg, domain, type_id, tariff, max_s)
    JOIN core.suppliers s       ON s.supplier_number = v.sn
    JOIN core.kindergartens k   ON k.kindergarten_code = v.kg
    JOIN ref.activity_domains d ON d.name_he = v.domain;

    SELECT e.engagement_id INTO v_e1 FROM core.engagements e
      JOIN core.suppliers s ON s.supplier_id = e.supplier_id JOIN core.kindergartens k ON k.kindergarten_id = e.kindergarten_id
     WHERE s.supplier_number = '900101' AND k.kindergarten_code = '900001';
    SELECT e.engagement_id INTO v_e2 FROM core.engagements e
      JOIN core.suppliers s ON s.supplier_id = e.supplier_id JOIN core.kindergartens k ON k.kindergarten_id = e.kindergarten_id
     WHERE s.supplier_number = '900101' AND k.kindergarten_code = '900002';
    SELECT c.contact_id INTO v_contact FROM core.supplier_contacts c
      JOIN core.suppliers s ON s.supplier_id = c.supplier_id
     WHERE s.supplier_number = '900101' ORDER BY c.contact_id LIMIT 1;

    INSERT INTO core.work_orders (engagement_id, order_seq, amount) VALUES (v_e1, 1, 7500.00), (v_e2, 1, 1250.00);

    /* דיווח 1: ספטמבר, גן ארגמן, אושר ע"י גננת (כולל שיעור כפול) */
    INSERT INTO ops.reports (engagement_id, report_year, report_month, status_id, submitted_by_contact_id, submitted_at)
    VALUES (v_e1, 2026, 9, 3, v_contact, '2026-10-02 08:00:00+00')
    RETURNING report_id INTO v_r1;
    INSERT INTO ops.report_lines (report_id, engagement_id, visit_date, session_type_id, tariff_applied, pay_multiplier, cap_units)
    SELECT v_r1, v_e1, v.d::date, st.session_type_id, 250.00, st.pay_multiplier, st.cap_units
    FROM (VALUES ('2026-09-07','REGULAR'), ('2026-09-14','DOUBLE'), ('2026-09-21','REGULAR'), ('2026-09-28','REGULAR')) v (d, t)
    JOIN ref.session_types st ON st.code = v.t;
    INSERT INTO ops.report_status_history (report_id, from_status_id, to_status_id, changed_at, actor_type, actor_id) VALUES
     (v_r1, NULL, 2, '2026-10-02 08:00:00+00', 'SUPPLIER_CONTACT', v_contact),
     (v_r1, 2,    3, '2026-10-02 13:30:00+00', 'TEACHER', (SELECT teacher_id FROM core.teachers WHERE mobile_phone = '0500000201'));

    /* דיווח 2: גן תאנה, 4 מתוך 5 מפגשים = מצב התראה (נותר 1) */
    INSERT INTO ops.reports (engagement_id, report_year, report_month, status_id, submitted_by_contact_id, submitted_at)
    VALUES (v_e2, 2026, 9, 2, v_contact, '2026-10-02 08:05:00+00')
    RETURNING report_id INTO v_r2;
    INSERT INTO ops.report_lines (report_id, engagement_id, visit_date, session_type_id, tariff_applied, pay_multiplier, cap_units)
    SELECT v_r2, v_e2, v.d::date, 1, 250.00, 1.00, 1
    FROM (VALUES ('2026-09-08'), ('2026-09-15'), ('2026-09-22'), ('2026-09-29')) v (d);

    /* אישור חריגה לדוגמה */
    INSERT INTO core.cap_overrides (engagement_id, extra_sessions, extra_amount, reason, approved_by_staff_user_id)
    VALUES (v_e2, 2, 500.00, 'הספק התקשר, הגננת ביקשה שני מפגשים נוספים לקראת חנוכה', v_referent);

    /* נעילת דיווח 1: הטריגר מכניס אותו אוטומטית לתור הייצוא לפרוסי */
    UPDATE ops.reports SET status_id = 6, final_approved_by_staff_user_id = v_referent, final_approved_at = '2026-10-05 09:00:00+00' WHERE report_id = v_r1;
    UPDATE ops.reports SET status_id = 7, locked_at = '2026-10-05 09:01:00+00' WHERE report_id = v_r1;
END $$;

COMMIT;

/* בדיקות מהירות */
SELECT * FROM core.vw_engagement_usage;               -- ההתקשרות של גן תאנה צריכה להופיע עם is_warning = true
SELECT * FROM core.vw_kindergarten_login_phones;      -- גן 900002: teachers_in_kg = 2
SELECT report_id, status, left(payload::text, 200) AS payload_start FROM procy.outbox;  -- דיווח 1 בתור
SELECT '05_test_data.sql הושלם' AS status;
