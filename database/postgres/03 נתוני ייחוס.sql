/* =====================================================================
   03_reference_data.sql  |  שלב א'  |  גרסת PostgreSQL (Supabase)
   רשימות קבועות והגדרות. להריץ אחרי 01 ו-02, בכל סביבה.
   ===================================================================== */
BEGIN;

/* ---------- שנות לימודים ----------
   ❌ טווח התאריכים (1.9 עד 31.8) הוא הנחה, לאישור צופיה.
   נתוני האקסל מסומנים תשפ"ו. השנה הנוכחית (אוקטובר 2026) היא תשפ"ז.   */
INSERT INTO ref.school_years (school_year_id, hebrew_name, start_date, end_date, is_current) VALUES
 (2026, 'תשפ"ו', '2025-09-01', '2026-08-31', false),
 (2027, 'תשפ"ז', '2026-09-01', '2027-08-31', true);

/* ---------- תחומי פעילות (מנורמלים מכ-200 ערכים חופשיים באקסל) ---------- */
INSERT INTO ref.activity_domains (name_he) VALUES
 ('ריתמיקה'), ('מוזיקה'), ('תיאטרון ודרמה'), ('תנועה וספורט'), ('יוגה'),
 ('חיות וטבע'), ('מדע'), ('גינון וקיימות'), ('יצירה ואומנות'), ('יהדות ומסורת'),
 ('מסיבות'), ('הסעות וטיולים');

/* ---------- סוגי התקשרות ---------- */
INSERT INTO ref.engagement_types (engagement_type_id, code, name_he, requires_supervisor_approval) VALUES
 (1, 'ANNUAL',        'שנתי רגיל',                false),
 (2, 'ONE_TIME',      'חד פעמי באישור מפקחת',     true),
 (3, 'TALAN_SURPLUS', 'תוספת מיתרת תל"ן',          true);

/* ---------- סוגי מפגש ----------
   שיעור כפול: משולם כתעריף כפול, נספר כמפגש אחד בתקרה (החלטה מאושרת) */
INSERT INTO ref.session_types (session_type_id, code, name_he, pay_multiplier, cap_units) VALUES
 (1, 'REGULAR', 'רגיל', 1.00, 1),
 (2, 'DOUBLE',  'כפול', 2.00, 1);

/* ---------- סטטוסי דיווח ---------- */
INSERT INTO ref.report_statuses (status_id, code, name_he, is_final, sort_order) VALUES
 (1, 'DRAFT',            'טיוטה',                 false, 1),
 (2, 'SENT_TO_TEACHER',  'ממתין לחתימת גננת',     false, 2),
 (3, 'TEACHER_APPROVED', 'אושר ע"י הגננת',        false, 3),
 (4, 'TEACHER_REJECTED', 'נדחה ע"י הגננת',        false, 4),
 (5, 'RETURNED',         'דורש תיקון',            false, 5),
 (6, 'STAFF_APPROVED',   'אושר סופית',            false, 6),
 (7, 'LOCKED',           'אושר ונעול',            true,  7);

/* ---------- סיבות דחייה ---------- */
INSERT INTO ref.rejection_reasons (rejection_reason_id, applies_to, name_he) VALUES
 (1,  'TEACHER', 'תאריך שגוי'),
 (2,  'TEACHER', 'מספר מפגשים שגוי'),
 (3,  'TEACHER', 'לא התקיימה פעילות'),
 (4,  'TEACHER', 'סוג מפגש שגוי (רגיל / כפול)'),
 (5,  'TEACHER', 'אחר'),
 (11, 'STAFF',   'תעריף לא תואם לחוזה'),
 (12, 'STAFF',   'חריגה מתקרה ללא אישור'),
 (13, 'STAFF',   'חסר אישור מפקחת'),
 (14, 'STAFF',   'כפילות מול דיווח קודם'),
 (15, 'STAFF',   'אחר');

/* ---------- תפקידי צוות ---------- */
INSERT INTO ref.staff_roles (role_id, code, name_he) VALUES
 (1, 'ADMIN',    'מנהלת מערכת'),
 (2, 'REFERENT', 'רפרנטית'),
 (3, 'VIEWER',   'צפייה בלבד');

/* ---------- הגדרות ----------  NULL = טרם הוחלט */
INSERT INTO ref.settings (setting_key, setting_value, value_type, description_he) VALUES
 ('SubmissionDayOfMonth',      '3',  'INT',  'היום בחודש שעד אליו מגישים את דיווח החודש הקודם'),
 ('OtpLength',                 '6',  'INT',  'מספר ספרות בקוד האימות'),
 ('OtpTtlMinutes',             '5',  'INT',  'תוקף קוד אימות בדקות'),
 ('OtpMaxAttempts',            '3',  'INT',  'ניסיונות שגויים עד נעילה'),
 ('OtpLockMinutes',            '5',  'INT',  'משך נעילת נייד בדקות'),
 ('OtpMaxSendsPerHour',        '5',  'INT',  'מקסימום קודים לנייד בשעה (מניעת הצפה ועלויות SMS)'),
 ('CapWarnRemainingSessions',  '3',  'INT',  'התראה לספק כשנותרו X מפגשים, או סכום של X מפגשים רגילים'),
 ('TeacherReminderDays',       NULL, 'INT',  'אחרי כמה ימים בלי אישור נשלחת תזכורת לגננת'),
 ('StaffEscalationDays',       NULL, 'INT',  'אחרי כמה ימים בלי אישור הרפרנטית מקבלת התראה'),
 ('SmsProvider',               'mgroup', 'TEXT', 'ספק שליחת SMS ושיחות קוליות'),
 ('SystemTimeZone',            'Asia/Jerusalem', 'TEXT', 'כל הזמנים נשמרים ב-UTC ומוצגים לפי אזור זה');
 -- במקור: 'Israel Standard Time' (שם אזור של Windows). ב-PostgreSQL ובשרתי Vercel השם הוא Asia/Jerusalem

COMMIT;

/* לוח חגים (ref.holidays) נשאר ריק בכוונה:
   יש למלא מתוך לוח החופשות הרשמי של משרד החינוך לשנה הרלוונטית. שבתות מזוהות אוטומטית באפליקציה. */

SELECT '03_reference_data.sql הושלם' AS status;
