/* =====================================================================
   05_test_data.sql  |  שלב א'  |  סביבת בדיקות בלבד!
   נתוני דוגמה עם שמות וטלפונים פיקטיביים (050-0000xxx), כדי שאף SMS
   לא יגיע לגננת או לספק אמיתיים בזמן בדיקות.
   להריץ אחרי 01 ו-03. לא להריץ על מסד הייצור.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @Y SMALLINT = 2027;   -- תשפ"ז

/* צוות */
INSERT INTO core.StaffUsers (FullName, Email, RoleId) VALUES
 (N'מנהלת בדיקות', N'admin.test@example.org', 1),
 (N'רפרנטית בדיקות', N'referent.test@example.org', 2);
DECLARE @Referent INT = (SELECT StaffUserId FROM core.StaffUsers WHERE Email = N'referent.test@example.org');

/* מפקחת */
INSERT INTO core.Supervisors (FullName, Email) VALUES (N'מפקחת לדוגמה', N'supervisor.test@example.org');
DECLARE @Sup INT = SCOPE_IDENTITY();

/* ספקים ואנשי קשר */
INSERT INTO core.Suppliers (SupplierNumber, Name, Email) VALUES
 ('900101', N'ריתמיקה לדוגמה', N'rhythm.test@example.org'),
 ('900102', N'תיאטרון לדוגמה', N'theatre.test@example.org'),
 ('900103', N'חוות חיות לדוגמה', NULL);
INSERT INTO core.SupplierContacts (SupplierId, FullName, MobilePhone, IsPrimary)
SELECT SupplierId, v.FullName, v.Phone, v.IsPrimary
FROM (VALUES ('900101', N'נעמה בדיקה', '0500000101', 1),
             ('900102', N'אביטל בדיקה', '0500000102', 1),
             ('900102', N'אילנית בדיקה', '0500000112', 0),   -- ספק עם שני אנשי קשר
             ('900103', N'גיא בדיקה', '0500000103', 1)) v (SupplierNumber, FullName, Phone, IsPrimary)
JOIN core.Suppliers s ON s.SupplierNumber = v.SupplierNumber;

/* גנים, גננות ושיבוצים */
INSERT INTO core.Kindergartens (KindergartenCode, Name, SupervisorId, ReferentStaffUserId, IsManualTrack) VALUES
 ('900001', N'גן ארגמן בדיקה', @Sup, @Referent, 0),
 ('900002', N'גן תאנה בדיקה',  @Sup, @Referent, 0),   -- שתי גננות
 ('900003', N'גן שחר בדיקה',   @Sup, @Referent, 1);   -- מסלול ידני
INSERT INTO core.Teachers (FullName, MobilePhone) VALUES
 (N'גננת א בדיקה', '0500000201'),
 (N'גננת ב בדיקה', '0500000202'),
 (N'גננת ג בדיקה', '0500000203'),
 (N'גננת ד בדיקה', '0500000204');
INSERT INTO core.TeacherAssignments (TeacherId, KindergartenId, ValidFrom, IsSubstitute)
SELECT t.TeacherId, k.KindergartenId, '2026-09-01', v.IsSub
FROM (VALUES ('0500000201','900001',0), ('0500000202','900002',0), ('0500000203','900002',0), ('0500000204','900003',0)) v (Phone, Kg, IsSub)
JOIN core.Teachers t      ON t.MobilePhone = v.Phone
JOIN core.Kindergartens k ON k.KindergartenCode = v.Kg;

/* אישור מפקחת להתקשרות חד פעמית */
INSERT INTO core.SupervisorApprovals (SupervisorId, ApprovedOn, RecordedByStaffUserId, Notes)
VALUES (@Sup, '2026-09-20', @Referent, N'אישור הצגת חנוכה, דוגמה');
DECLARE @SupAppr INT = SCOPE_IDENTITY();

/* התקשרויות */
INSERT INTO core.Engagements (SchoolYearId, SupplierId, KindergartenId, DomainId, EngagementTypeId, TariffPerSession, MaxSessions, AnnualBudget, SupervisorApprovalId)
SELECT @Y, s.SupplierId, k.KindergartenId, d.DomainId, v.TypeId, v.Tariff, v.MaxS, v.Tariff * v.MaxS, CASE WHEN v.TypeId = 1 THEN NULL ELSE @SupAppr END
FROM (VALUES ('900101','900001',N'ריתמיקה',      1, 250.00, 30),
             ('900101','900002',N'ריתמיקה',      1, 250.00,  5),   -- תקרה נמוכה לבדיקת התראה וחסימה
             ('900102','900001',N'תיאטרון ודרמה',2, 900.00,  1),   -- חד פעמי
             ('900103','900003',N'חיות וטבע',    1, 260.00, 20)) v (Sn, Kg, Domain, TypeId, Tariff, MaxS)
JOIN core.Suppliers s      ON s.SupplierNumber = v.Sn
JOIN core.Kindergartens k  ON k.KindergartenCode = v.Kg
JOIN ref.ActivityDomains d ON d.NameHe = v.Domain;

DECLARE @E1 INT = (SELECT e.EngagementId FROM core.Engagements e JOIN core.Suppliers s ON s.SupplierId = e.SupplierId JOIN core.Kindergartens k ON k.KindergartenId = e.KindergartenId WHERE s.SupplierNumber = '900101' AND k.KindergartenCode = '900001');
DECLARE @E2 INT = (SELECT e.EngagementId FROM core.Engagements e JOIN core.Suppliers s ON s.SupplierId = e.SupplierId JOIN core.Kindergartens k ON k.KindergartenId = e.KindergartenId WHERE s.SupplierNumber = '900101' AND k.KindergartenCode = '900002');
DECLARE @Contact INT = (SELECT TOP 1 c.ContactId FROM core.SupplierContacts c JOIN core.Suppliers s ON s.SupplierId = c.SupplierId WHERE s.SupplierNumber = '900101');

INSERT INTO core.WorkOrders (EngagementId, OrderSeq, Amount) VALUES (@E1, 1, 7500.00), (@E2, 1, 1250.00);

/* דיווח 1: ספטמבר, גן ארגמן, אושר ע"י גננת (כולל שיעור כפול) */
INSERT INTO ops.Reports (EngagementId, ReportYear, ReportMonth, StatusId, SubmittedByContactId, SubmittedAt)
VALUES (@E1, 2026, 9, 3, @Contact, '2026-10-02T08:00:00');
DECLARE @R1 INT = SCOPE_IDENTITY();
INSERT INTO ops.ReportLines (ReportId, EngagementId, VisitDate, SessionTypeId, TariffApplied, PayMultiplier, CapUnits)
SELECT @R1, @E1, v.D, st.SessionTypeId, 250.00, st.PayMultiplier, st.CapUnits
FROM (VALUES ('2026-09-07','REGULAR'), ('2026-09-14','DOUBLE'), ('2026-09-21','REGULAR'), ('2026-09-28','REGULAR')) v (D, T)
JOIN ref.SessionTypes st ON st.Code = v.T;
INSERT INTO ops.ReportStatusHistory (ReportId, FromStatusId, ToStatusId, ChangedAt, ActorType, ActorId) VALUES
 (@R1, NULL, 2, '2026-10-02T08:00:00', 'SUPPLIER_CONTACT', @Contact),
 (@R1, 2,    3, '2026-10-02T13:30:00', 'TEACHER', (SELECT TeacherId FROM core.Teachers WHERE MobilePhone = '0500000201'));

/* דיווח 2: גן תאנה, 4 מתוך 5 מפגשים = מצב התראה (נותר 1) */
INSERT INTO ops.Reports (EngagementId, ReportYear, ReportMonth, StatusId, SubmittedByContactId, SubmittedAt)
VALUES (@E2, 2026, 9, 2, @Contact, '2026-10-02T08:05:00');
DECLARE @R2 INT = SCOPE_IDENTITY();
INSERT INTO ops.ReportLines (ReportId, EngagementId, VisitDate, SessionTypeId, TariffApplied, PayMultiplier, CapUnits)
SELECT @R2, @E2, v.D, 1, 250.00, 1.00, 1
FROM (VALUES ('2026-09-08'), ('2026-09-15'), ('2026-09-22'), ('2026-09-29')) v (D);

/* אישור חריגה לדוגמה */
INSERT INTO core.CapOverrides (EngagementId, ExtraSessions, ExtraAmount, Reason, ApprovedByStaffUserId)
VALUES (@E2, 2, 500.00, N'הספק התקשר, הגננת ביקשה שני מפגשים נוספים לקראת חנוכה', @Referent);

/* נעילת דיווח 1: הטריגר מכניס אותו אוטומטית לתור הייצוא לפרוסי */
UPDATE ops.Reports SET StatusId = 6, FinalApprovedByStaffUserId = @Referent, FinalApprovedAt = '2026-10-05T09:00:00' WHERE ReportId = @R1;
UPDATE ops.Reports SET StatusId = 7, LockedAt = '2026-10-05T09:01:00' WHERE ReportId = @R1;

COMMIT TRANSACTION;

/* בדיקות מהירות */
SELECT * FROM core.vw_EngagementUsage;            -- @E2 צריך להופיע עם IsWarning = 1
SELECT * FROM core.vw_KindergartenLoginPhones;    -- גן 900002: TeachersInKg = 2
SELECT ReportId, Status, LEFT(Payload, 200) AS PayloadStart FROM procy.Outbox;  -- דיווח 1 בתור
PRINT N'05_test_data.sql הושלם';
GO
