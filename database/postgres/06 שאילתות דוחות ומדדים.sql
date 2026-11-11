/* =====================================================================
   06_report_queries.sql  |  גרסת PostgreSQL (Supabase)
   שאילתות דוחות ומדדים (KPI) למערכת דיווח הגנים · שלב א'
   כל שאילתה עומדת בפני עצמה (קריאה בלבד). הפרמטרים מוגדרים בתחילת כל אחת,
   בבלוק params. ב-SQL Editor של Supabase: לסמן שאילתה אחת ולהריץ.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. דוח תשלום חודשי לפי ספק
   מה מקבלים: לכל ספק, כמה גנים, כמה מפגשים (רגילים וכפולים) והסכום לתשלום
   בחודש נבחר. נספרים רק דיווחים שאושרו סופית או ננעלו.
   --------------------------------------------------------------------- */
WITH params AS (SELECT 2026 AS p_year, 10 AS p_month)
SELECT  s.supplier_number                                   AS "מספר ספק",
        s.name                                              AS "ספק",
        count(DISTINCT e.kindergarten_id)                   AS "גנים",
        count(l.report_line_id)                             AS "ימי פעילות",
        count(*) FILTER (WHERE st.code = 'DOUBLE')          AS "מתוכם כפולים",
        sum(l.line_amount)                                  AS "לתשלום"
FROM    params p
JOIN    ops.reports        r  ON r.report_year = p.p_year AND r.report_month = p.p_month
JOIN    ref.report_statuses rs ON rs.status_id     = r.status_id
JOIN    core.engagements   e  ON e.engagement_id  = r.engagement_id
JOIN    core.suppliers     s  ON s.supplier_id    = e.supplier_id
JOIN    ops.report_lines   l  ON l.report_id      = r.report_id
JOIN    ref.session_types  st ON st.session_type_id = l.session_type_id
WHERE   rs.code IN ('STAFF_APPROVED', 'LOCKED')
GROUP BY s.supplier_number, s.name
ORDER BY "לתשלום" DESC;

/* ---------------------------------------------------------------------
   2. התקשרויות שמתקרבות לתקרה או עברו אותה
   מה מקבלים: רשימת התקשרויות עם התראה, לפי מה שנשאר עד התקרה.
   משתמשת בתצוגה core.vw_engagement_usage שכבר מחשבת ניצול.
   --------------------------------------------------------------------- */
SELECT  s.name                       AS "ספק",
        k.name                       AS "גן",
        d.name_he                    AS "תחום",
        u.sessions_used              AS "מפגשים שנוצלו",
        u.session_cap                AS "תקרת מפגשים",
        u.sessions_remaining         AS "נותרו מפגשים",
        u.amount_remaining           AS "נותר בכסף",
        CASE WHEN u.is_blocked THEN 'הגיע לתקרה' ELSE 'מתקרב לתקרה' END AS "מצב"
FROM    core.vw_engagement_usage u
JOIN    core.engagements    e ON e.engagement_id   = u.engagement_id
JOIN    core.suppliers      s ON s.supplier_id     = u.supplier_id
JOIN    core.kindergartens  k ON k.kindergarten_id = u.kindergarten_id
JOIN    ref.activity_domains d ON d.domain_id      = e.domain_id
JOIN    ref.school_years    y ON y.school_year_id  = u.school_year_id
WHERE   y.is_current
  AND   e.is_active
  AND   u.is_warning
ORDER BY u.is_blocked DESC, u.sessions_remaining ASC;

/* ---------------------------------------------------------------------
   3. דיווחים שממתינים לחתימת גננת, לפי גן
   מה מקבלים: לכל גן, כמה דיווחים מחכים לחתימה וכמה ימים מחכה הוותיק שבהם.
   משמש לתזכורות ולמעקב של הרפרנטית.
   --------------------------------------------------------------------- */
WITH params AS (SELECT 3 AS p_min_days)
SELECT  k.kindergarten_code                                          AS "סמל גן",
        k.name                                                       AS "גן",
        count(*)                                                     AS "דיווחים ממתינים",
        max((now() AT TIME ZONE 'UTC')::date - (r.submitted_at AT TIME ZONE 'UTC')::date) AS "ימים בהמתנה (המקסימום)"
FROM    ops.reports        r
JOIN    ref.report_statuses rs ON rs.status_id     = r.status_id
JOIN    core.engagements   e  ON e.engagement_id  = r.engagement_id
JOIN    core.kindergartens k  ON k.kindergarten_id = e.kindergarten_id
CROSS JOIN params p
WHERE   rs.code = 'SENT_TO_TEACHER'
GROUP BY k.kindergarten_code, k.name, p.p_min_days
HAVING  max((now() AT TIME ZONE 'UTC')::date - (r.submitted_at AT TIME ZONE 'UTC')::date) >= p.p_min_days
ORDER BY "ימים בהמתנה (המקסימום)" DESC;

/* ---------------------------------------------------------------------
   4. מדד: זמן טיפול ממוצע בדיווח, לפי חודש
   מה מקבלים: כמה ימים עוברים בממוצע משליחת הדיווח ועד האישור הסופי.
   זה המדד המרכזי להשוואה מול התהליך הידני.
   --------------------------------------------------------------------- */
SELECT  r.report_year                                                                     AS "שנה",
        r.report_month                                                                    AS "חודש",
        count(*)                                                                          AS "דיווחים שאושרו",
        round(avg(extract(epoch FROM r.final_approved_at - r.submitted_at) / 86400.0), 1) AS "ימים בממוצע",
        max((r.final_approved_at AT TIME ZONE 'UTC')::date - (r.submitted_at AT TIME ZONE 'UTC')::date) AS "הארוך ביותר (ימים)"
FROM    ops.reports r
WHERE   r.submitted_at IS NOT NULL
  AND   r.final_approved_at IS NOT NULL
GROUP BY r.report_year, r.report_month
ORDER BY r.report_year, r.report_month;

/* ---------------------------------------------------------------------
   5. מדד: אחוז דיווחים שהוחזרו לתיקון או נדחו, לפי ספק
   מה מקבלים: אצל אילו ספקים יש הכי הרבה טעויות בדיווח.
   דיווח נספר פעם אחת גם אם הוחזר כמה פעמים.
   --------------------------------------------------------------------- */
WITH bounced AS (
    SELECT  DISTINCT h.report_id
    FROM    ops.report_status_history h
    JOIN    ref.report_statuses rs ON rs.status_id = h.to_status_id
    WHERE   rs.code IN ('TEACHER_REJECTED', 'RETURNED')
)
SELECT  s.name                                                     AS "ספק",
        count(*)                                                   AS "דיווחים",
        count(b.report_id)                                         AS "הוחזרו או נדחו",
        round(100.0 * count(b.report_id) / count(*), 1)            AS "אחוז"
FROM    ops.reports      r
JOIN    core.engagements e ON e.engagement_id = r.engagement_id
JOIN    core.suppliers   s ON s.supplier_id   = e.supplier_id
LEFT JOIN bounced        b ON b.report_id     = r.report_id
WHERE   r.submitted_at IS NOT NULL
GROUP BY s.name
HAVING  count(b.report_id) > 0
ORDER BY "אחוז" DESC;

/* ---------------------------------------------------------------------
   6. מדד: אחוז אישורים דיגיטליים, לפי חודש
   מה מקבלים: כמה מהדיווחים אושרו בחתימה דיגיטלית של הגננת,
   וכמה עדיין עברו במסלול הידני (טופס נייר שהוזן על ידי הצוות).
   --------------------------------------------------------------------- */
SELECT  r.report_year                                                     AS "שנה",
        r.report_month                                                    AS "חודש",
        count(*)                                                          AS "דיווחים",
        count(*) FILTER (WHERE NOT r.is_manual)                           AS "דיגיטליים",
        count(*) FILTER (WHERE r.is_manual)                               AS "ידניים",
        round(100.0 * count(*) FILTER (WHERE NOT r.is_manual) / count(*), 1) AS "אחוז דיגיטלי"
FROM    ops.reports        r
JOIN    ref.report_statuses rs ON rs.status_id = r.status_id
WHERE   rs.code IN ('TEACHER_APPROVED', 'STAFF_APPROVED', 'LOCKED')
GROUP BY r.report_year, r.report_month
ORDER BY r.report_year, r.report_month;
