/* =====================================================================
   06_report_queries.sql
   שאילתות דוחות ומדדים (KPI) למערכת דיווח הגנים · שלב א'
   כל שאילתה עומדת בפני עצמה. הפרמטרים מוגדרים בתחילת כל אחת.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. דוח תשלום חודשי לפי ספק
   מה מקבלים: לכל ספק, כמה גנים, כמה מפגשים (רגילים וכפולים) והסכום לתשלום
   בחודש נבחר. נספרים רק דיווחים שאושרו סופית או ננעלו.
   --------------------------------------------------------------------- */
DECLARE @Year SMALLINT = 2026, @Month TINYINT = 10;

SELECT  s.SupplierNumber                                   AS [מספר ספק],
        s.Name                                             AS [ספק],
        COUNT(DISTINCT e.KindergartenId)                   AS [גנים],
        COUNT(l.ReportLineId)                              AS [ימי פעילות],
        SUM(CASE WHEN st.Code = 'DOUBLE' THEN 1 ELSE 0 END) AS [מתוכם כפולים],
        SUM(l.LineAmount)                                  AS [לתשלום]
FROM    ops.Reports        r
JOIN    ref.ReportStatuses rs ON rs.StatusId     = r.StatusId
JOIN    core.Engagements   e  ON e.EngagementId  = r.EngagementId
JOIN    core.Suppliers     s  ON s.SupplierId    = e.SupplierId
JOIN    ops.ReportLines    l  ON l.ReportId      = r.ReportId
JOIN    ref.SessionTypes   st ON st.SessionTypeId = l.SessionTypeId
WHERE   r.ReportYear = @Year
  AND   r.ReportMonth = @Month
  AND   rs.Code IN ('STAFF_APPROVED', 'LOCKED')
GROUP BY s.SupplierNumber, s.Name
ORDER BY [לתשלום] DESC;
GO

/* ---------------------------------------------------------------------
   2. התקשרויות שמתקרבות לתקרה או עברו אותה
   מה מקבלים: רשימת התקשרויות עם התראה, לפי מה שנשאר עד התקרה.
   משתמשת בתצוגה core.vw_EngagementUsage שכבר מחשבת ניצול.
   --------------------------------------------------------------------- */
SELECT  s.Name                       AS [ספק],
        k.Name                       AS [גן],
        d.NameHe                     AS [תחום],
        u.SessionsUsed               AS [מפגשים שנוצלו],
        u.SessionCap                 AS [תקרת מפגשים],
        u.SessionsRemaining          AS [נותרו מפגשים],
        u.AmountRemaining            AS [נותר בכסף],
        CASE WHEN u.IsBlocked = 1 THEN N'הגיע לתקרה' ELSE N'מתקרב לתקרה' END AS [מצב]
FROM    core.vw_EngagementUsage u
JOIN    core.Engagements    e ON e.EngagementId   = u.EngagementId
JOIN    core.Suppliers      s ON s.SupplierId     = u.SupplierId
JOIN    core.Kindergartens  k ON k.KindergartenId = u.KindergartenId
JOIN    ref.ActivityDomains d ON d.DomainId       = e.DomainId
JOIN    ref.SchoolYears     y ON y.SchoolYearId   = u.SchoolYearId
WHERE   y.IsCurrent = 1
  AND   e.IsActive = 1
  AND   u.IsWarning = 1
ORDER BY u.IsBlocked DESC, u.SessionsRemaining ASC;
GO

/* ---------------------------------------------------------------------
   3. דיווחים שממתינים לחתימת גננת, לפי גן
   מה מקבלים: לכל גן, כמה דיווחים מחכים לחתימה וכמה ימים מחכה הוותיק שבהם.
   משמש לתזכורות ולמעקב של הרפרנטית.
   --------------------------------------------------------------------- */
SELECT  k.KindergartenCode                                  AS [סמל גן],
        k.Name                                              AS [גן],
        COUNT(*)                                            AS [דיווחים ממתינים],
        MAX(DATEDIFF(DAY, r.SubmittedAt, SYSUTCDATETIME())) AS [ימים בהמתנה (המקסימום)]
FROM    ops.Reports        r
JOIN    ref.ReportStatuses rs ON rs.StatusId     = r.StatusId
JOIN    core.Engagements   e  ON e.EngagementId  = r.EngagementId
JOIN    core.Kindergartens k  ON k.KindergartenId = e.KindergartenId
WHERE   rs.Code = 'SENT_TO_TEACHER'
GROUP BY k.KindergartenCode, k.Name
HAVING  MAX(DATEDIFF(DAY, r.SubmittedAt, SYSUTCDATETIME())) >= 3
ORDER BY [ימים בהמתנה (המקסימום)] DESC;
GO

/* ---------------------------------------------------------------------
   4. מדד: זמן טיפול ממוצע בדיווח, לפי חודש
   מה מקבלים: כמה ימים עוברים בממוצע משליחת הדיווח ועד האישור הסופי.
   זה המדד המרכזי להשוואה מול התהליך הידני.
   --------------------------------------------------------------------- */
SELECT  r.ReportYear                                                          AS [שנה],
        r.ReportMonth                                                         AS [חודש],
        COUNT(*)                                                              AS [דיווחים שאושרו],
        CAST(AVG(DATEDIFF(HOUR, r.SubmittedAt, r.FinalApprovedAt) / 24.0) AS DECIMAL(6,1)) AS [ימים בממוצע],
        MAX(DATEDIFF(DAY, r.SubmittedAt, r.FinalApprovedAt))                  AS [הארוך ביותר (ימים)]
FROM    ops.Reports r
WHERE   r.SubmittedAt IS NOT NULL
  AND   r.FinalApprovedAt IS NOT NULL
GROUP BY r.ReportYear, r.ReportMonth
ORDER BY r.ReportYear, r.ReportMonth;
GO

/* ---------------------------------------------------------------------
   5. מדד: אחוז דיווחים שהוחזרו לתיקון או נדחו, לפי ספק
   מה מקבלים: אצל אילו ספקים יש הכי הרבה טעויות בדיווח.
   דיווח נספר פעם אחת גם אם הוחזר כמה פעמים.
   --------------------------------------------------------------------- */
WITH Bounced AS (
    SELECT  DISTINCT h.ReportId
    FROM    ops.ReportStatusHistory h
    JOIN    ref.ReportStatuses rs ON rs.StatusId = h.ToStatusId
    WHERE   rs.Code IN ('TEACHER_REJECTED', 'RETURNED')
)
SELECT  s.Name                                                    AS [ספק],
        COUNT(*)                                                  AS [דיווחים],
        COUNT(b.ReportId)                                         AS [הוחזרו או נדחו],
        CAST(100.0 * COUNT(b.ReportId) / COUNT(*) AS DECIMAL(5,1)) AS [אחוז]
FROM    ops.Reports      r
JOIN    core.Engagements e ON e.EngagementId = r.EngagementId
JOIN    core.Suppliers   s ON s.SupplierId   = e.SupplierId
LEFT JOIN Bounced        b ON b.ReportId     = r.ReportId
WHERE   r.SubmittedAt IS NOT NULL
GROUP BY s.Name
HAVING  COUNT(b.ReportId) > 0
ORDER BY [אחוז] DESC;
GO

/* ---------------------------------------------------------------------
   6. מדד: אחוז אישורים דיגיטליים, לפי חודש
   מה מקבלים: כמה מהדיווחים אושרו בחתימה דיגיטלית של הגננת,
   וכמה עדיין עברו במסלול הידני (טופס נייר שהוזן על ידי הצוות).
   --------------------------------------------------------------------- */
SELECT  r.ReportYear                                                          AS [שנה],
        r.ReportMonth                                                         AS [חודש],
        COUNT(*)                                                              AS [דיווחים],
        SUM(CASE WHEN r.IsManual = 0 THEN 1 ELSE 0 END)                       AS [דיגיטליים],
        SUM(CASE WHEN r.IsManual = 1 THEN 1 ELSE 0 END)                       AS [ידניים],
        CAST(100.0 * SUM(CASE WHEN r.IsManual = 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS [אחוז דיגיטלי]
FROM    ops.Reports        r
JOIN    ref.ReportStatuses rs ON rs.StatusId = r.StatusId
WHERE   rs.Code IN ('TEACHER_APPROVED', 'STAFF_APPROVED', 'LOCKED')
GROUP BY r.ReportYear, r.ReportMonth
ORDER BY r.ReportYear, r.ReportMonth;
GO
