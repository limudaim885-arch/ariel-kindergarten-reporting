/* =====================================================================
   03_reference_data.sql  |  שלב א'
   רשימות קבועות והגדרות. להריץ אחרי 01 (ו-02 אם רלוונטי), בכל סביבה.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

/* ---------- שנות לימודים ----------
   ❌ טווח התאריכים (1.9 עד 31.8) הוא הנחה, לאישור צופיה.
   נתוני האקסל מסומנים תשפ"ו. השנה הנוכחית (אוקטובר 2026) היא תשפ"ז.   */
INSERT INTO ref.SchoolYears (SchoolYearId, HebrewName, StartDate, EndDate, IsCurrent) VALUES
 (2026, N'תשפ"ו', '2025-09-01', '2026-08-31', 0),
 (2027, N'תשפ"ז', '2026-09-01', '2027-08-31', 1);

/* ---------- תחומי פעילות (מנורמלים מכ-200 ערכים חופשיים באקסל) ---------- */
INSERT INTO ref.ActivityDomains (NameHe) VALUES
 (N'ריתמיקה'), (N'מוזיקה'), (N'תיאטרון ודרמה'), (N'תנועה וספורט'), (N'יוגה'),
 (N'חיות וטבע'), (N'מדע'), (N'גינון וקיימות'), (N'יצירה ואומנות'), (N'יהדות ומסורת'),
 (N'מסיבות'), (N'הסעות וטיולים');

/* ---------- סוגי התקשרות ---------- */
INSERT INTO ref.EngagementTypes (EngagementTypeId, Code, NameHe, RequiresSupervisorApproval) VALUES
 (1, 'ANNUAL',        N'שנתי רגיל',                0),
 (2, 'ONE_TIME',      N'חד פעמי באישור מפקחת',     1),
 (3, 'TALAN_SURPLUS', N'תוספת מיתרת תל"ן',          1);

/* ---------- סוגי מפגש ----------
   שיעור כפול: משולם כתעריף כפול, נספר כמפגש אחד בתקרה (החלטה מאושרת) */
INSERT INTO ref.SessionTypes (SessionTypeId, Code, NameHe, PayMultiplier, CapUnits) VALUES
 (1, 'REGULAR', N'רגיל', 1.00, 1),
 (2, 'DOUBLE',  N'כפול', 2.00, 1);

/* ---------- סטטוסי דיווח ---------- */
INSERT INTO ref.ReportStatuses (StatusId, Code, NameHe, IsFinal, SortOrder) VALUES
 (1, 'DRAFT',            N'טיוטה',                 0, 1),
 (2, 'SENT_TO_TEACHER',  N'ממתין לחתימת גננת',     0, 2),
 (3, 'TEACHER_APPROVED', N'אושר ע"י הגננת',        0, 3),
 (4, 'TEACHER_REJECTED', N'נדחה ע"י הגננת',        0, 4),
 (5, 'RETURNED',         N'דורש תיקון',            0, 5),
 (6, 'STAFF_APPROVED',   N'אושר סופית',            0, 6),
 (7, 'LOCKED',           N'אושר ונעול',            1, 7);

/* ---------- סיבות דחייה ---------- */
INSERT INTO ref.RejectionReasons (RejectionReasonId, AppliesTo, NameHe) VALUES
 (1,  'TEACHER', N'תאריך שגוי'),
 (2,  'TEACHER', N'מספר מפגשים שגוי'),
 (3,  'TEACHER', N'לא התקיימה פעילות'),
 (4,  'TEACHER', N'סוג מפגש שגוי (רגיל / כפול)'),
 (5,  'TEACHER', N'אחר'),
 (11, 'STAFF',   N'תעריף לא תואם לחוזה'),
 (12, 'STAFF',   N'חריגה מתקרה ללא אישור'),
 (13, 'STAFF',   N'חסר אישור מפקחת'),
 (14, 'STAFF',   N'כפילות מול דיווח קודם'),
 (15, 'STAFF',   N'אחר');

/* ---------- תפקידי צוות ---------- */
INSERT INTO ref.StaffRoles (RoleId, Code, NameHe) VALUES
 (1, 'ADMIN',    N'מנהלת מערכת'),
 (2, 'REFERENT', N'רפרנטית'),
 (3, 'VIEWER',   N'צפייה בלבד');

/* ---------- הגדרות ----------  NULL = טרם הוחלט */
INSERT INTO ref.Settings (SettingKey, SettingValue, ValueType, DescriptionHe) VALUES
 ('SubmissionDayOfMonth',      N'3',  'INT',  N'היום בחודש שעד אליו מגישים את דיווח החודש הקודם'),
 ('OtpLength',                 N'6',  'INT',  N'מספר ספרות בקוד האימות'),
 ('OtpTtlMinutes',             N'5',  'INT',  N'תוקף קוד אימות בדקות'),
 ('OtpMaxAttempts',            N'3',  'INT',  N'ניסיונות שגויים עד נעילה'),
 ('OtpLockMinutes',            N'5',  'INT',  N'משך נעילת נייד בדקות'),
 ('OtpMaxSendsPerHour',        N'5',  'INT',  N'מקסימום קודים לנייד בשעה (מניעת הצפה ועלויות SMS)'),
 ('CapWarnRemainingSessions',  N'3',  'INT',  N'התראה לספק כשנותרו X מפגשים, או סכום של X מפגשים רגילים'),
 ('TeacherReminderDays',       NULL,  'INT',  N'אחרי כמה ימים בלי אישור נשלחת תזכורת לגננת'),
 ('StaffEscalationDays',       NULL,  'INT',  N'אחרי כמה ימים בלי אישור הרפרנטית מקבלת התראה'),
 ('SmsProvider',               N'mgroup', 'TEXT', N'ספק שליחת SMS ושיחות קוליות'),
 ('SystemTimeZone',            N'Israel Standard Time', 'TEXT', N'כל הזמנים נשמרים ב-UTC ומוצגים לפי אזור זה');

COMMIT TRANSACTION;

/* לוח חגים (ref.Holidays) נשאר ריק בכוונה:
   יש למלא מתוך לוח החופשות הרשמי של משרד החינוך לשנה הרלוונטית. שבתות מזוהות אוטומטית באפליקציה. */

PRINT N'03_reference_data.sql הושלם';
GO
