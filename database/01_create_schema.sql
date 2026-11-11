/* =====================================================================
   מערכת דיווח גנים, חברה עירונית אריאל
   01_create_schema.sql  |  שלב א'
   יצירת סכמות, טבלאות, אילוצים ותצוגות
   ---------------------------------------------------------------------
   יעד:      SQL Server 2016 ומעלה (מקומי)
   הרצה:     על מסד ריק. להריץ פעם אחת בסביבת בדיקות ופעם אחת בייצור.
   קידוד:    כל טקסט NVARCHAR (עברית). סכומים DECIMAL. זמנים DATETIME2(0) ב-UTC.
   מחיקה:    אין מחיקה פיזית של ישויות עסקיות, רק IsActive = 0.
   ===================================================================== */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ---------- סכמות ---------- */
IF SCHEMA_ID(N'ref')   IS NULL EXEC(N'CREATE SCHEMA ref');    -- רשימות קבועות והגדרות
GO
IF SCHEMA_ID(N'core')  IS NULL EXEC(N'CREATE SCHEMA core');   -- נתוני מאסטר: ספקים, גנים, גננות, התקשרויות
GO
IF SCHEMA_ID(N'ops')   IS NULL EXEC(N'CREATE SCHEMA ops');    -- דיווחים, אישורים, הודעות
GO
IF SCHEMA_ID(N'auth')  IS NULL EXEC(N'CREATE SCHEMA auth');   -- קודי אימות ונעילות
GO
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit');  -- יומן פעולות
GO
IF SCHEMA_ID(N'procy') IS NULL EXEC(N'CREATE SCHEMA procy');  -- תשתית לחיבור לפרוסי (שלב ב')
GO
IF SCHEMA_ID(N'stg')   IS NULL EXEC(N'CREATE SCHEMA stg');    -- ייבוא ודחויים
GO

/* =====================================================================
   ref : רשימות קבועות
   ===================================================================== */

CREATE TABLE ref.SchoolYears (
    SchoolYearId   SMALLINT      NOT NULL CONSTRAINT PK_SchoolYears PRIMARY KEY,   -- למשל 2026 = תשפ"ו (השנה שבה היא מסתיימת)
    HebrewName     NVARCHAR(10)  NOT NULL CONSTRAINT UQ_SchoolYears_Name UNIQUE,   -- תשפ"ו
    StartDate      DATE          NOT NULL,
    EndDate        DATE          NOT NULL,
    IsCurrent      BIT           NOT NULL CONSTRAINT DF_SchoolYears_IsCurrent DEFAULT (0),
    CONSTRAINT CK_SchoolYears_Dates CHECK (EndDate > StartDate)
);
CREATE UNIQUE INDEX UX_SchoolYears_OneCurrent ON ref.SchoolYears (IsCurrent) WHERE IsCurrent = 1;
GO

CREATE TABLE ref.ActivityDomains (            -- תחום פעילות: ריתמיקה, תיאטרון, יוגה...
    DomainId       SMALLINT      NOT NULL IDENTITY(1,1) CONSTRAINT PK_ActivityDomains PRIMARY KEY,
    NameHe         NVARCHAR(50)  NOT NULL CONSTRAINT UQ_ActivityDomains_Name UNIQUE,
    IsActive       BIT           NOT NULL CONSTRAINT DF_ActivityDomains_IsActive DEFAULT (1)
);
GO

CREATE TABLE ref.EngagementTypes (            -- סוג התקשרות
    EngagementTypeId           TINYINT       NOT NULL CONSTRAINT PK_EngagementTypes PRIMARY KEY,
    Code                       VARCHAR(20)   NOT NULL CONSTRAINT UQ_EngagementTypes_Code UNIQUE,
    NameHe                     NVARCHAR(60)  NOT NULL,
    RequiresSupervisorApproval BIT           NOT NULL   -- חד פעמי ותוספת מיתרה דורשים אישור מפקחת
);
GO

CREATE TABLE ref.SessionTypes (               -- סוג מפגש בשורת דיווח
    SessionTypeId  TINYINT       NOT NULL CONSTRAINT PK_SessionTypes PRIMARY KEY,
    Code           VARCHAR(20)   NOT NULL CONSTRAINT UQ_SessionTypes_Code UNIQUE,
    NameHe         NVARCHAR(30)  NOT NULL,
    PayMultiplier  DECIMAL(4,2)  NOT NULL,   -- כפול = 2.00 (מתומחר כתעריף כפול)
    CapUnits       TINYINT       NOT NULL,   -- כפול = 1 (נספר כמפגש אחד בתקרה)
    CONSTRAINT CK_SessionTypes_Values CHECK (PayMultiplier > 0 AND CapUnits >= 0)
);
GO

CREATE TABLE ref.ReportStatuses (
    StatusId       TINYINT       NOT NULL CONSTRAINT PK_ReportStatuses PRIMARY KEY,
    Code           VARCHAR(30)   NOT NULL CONSTRAINT UQ_ReportStatuses_Code UNIQUE,
    NameHe         NVARCHAR(40)  NOT NULL,
    IsFinal        BIT           NOT NULL,
    SortOrder      TINYINT       NOT NULL
);
GO

CREATE TABLE ref.RejectionReasons (           -- סיבות דחייה מרשימה סגורה
    RejectionReasonId TINYINT     NOT NULL CONSTRAINT PK_RejectionReasons PRIMARY KEY,
    AppliesTo      VARCHAR(10)   NOT NULL,   -- TEACHER | STAFF
    NameHe         NVARCHAR(80)  NOT NULL,
    IsActive       BIT           NOT NULL CONSTRAINT DF_RejectionReasons_IsActive DEFAULT (1),
    CONSTRAINT CK_RejectionReasons_AppliesTo CHECK (AppliesTo IN ('TEACHER','STAFF'))
);
GO

CREATE TABLE ref.StaffRoles (
    RoleId         TINYINT       NOT NULL CONSTRAINT PK_StaffRoles PRIMARY KEY,
    Code           VARCHAR(20)   NOT NULL CONSTRAINT UQ_StaffRoles_Code UNIQUE,
    NameHe         NVARCHAR(40)  NOT NULL
);
GO

CREATE TABLE ref.Holidays (                   -- חגים וימים ללא פעילות בגנים
    HolidayDate    DATE          NOT NULL CONSTRAINT PK_Holidays PRIMARY KEY,
    NameHe         NVARCHAR(60)  NOT NULL,
    SchoolYearId   SMALLINT      NULL CONSTRAINT FK_Holidays_SchoolYear REFERENCES ref.SchoolYears (SchoolYearId)
);
GO

CREATE TABLE ref.Settings (                   -- הגדרות מערכת, במקום ערכים קבועים בקוד
    SettingKey     VARCHAR(60)   NOT NULL CONSTRAINT PK_Settings PRIMARY KEY,
    SettingValue   NVARCHAR(200) NULL,       -- NULL = טרם הוחלט
    ValueType      VARCHAR(10)   NOT NULL,   -- INT | DECIMAL | TEXT | BOOL
    DescriptionHe  NVARCHAR(300) NOT NULL,
    UpdatedAt      DATETIME2(0)  NOT NULL CONSTRAINT DF_Settings_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedBy      NVARCHAR(100) NULL,
    CONSTRAINT CK_Settings_Type CHECK (ValueType IN ('INT','DECIMAL','TEXT','BOOL'))
);
GO

/* =====================================================================
   core : נתוני מאסטר
   ===================================================================== */

CREATE TABLE core.StaffUsers (                -- צוות אריאל: דבורה, צופיה, רפרנטיות
    StaffUserId    INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_StaffUsers PRIMARY KEY,
    FullName       NVARCHAR(100) NOT NULL,
    Email          NVARCHAR(254) NOT NULL CONSTRAINT UQ_StaffUsers_Email UNIQUE,
    WindowsLogin   NVARCHAR(100) NULL,       -- אם הכניסה תהיה דרך Active Directory
    RoleId         TINYINT       NOT NULL CONSTRAINT FK_StaffUsers_Role REFERENCES ref.StaffRoles (RoleId),
    IsActive       BIT           NOT NULL CONSTRAINT DF_StaffUsers_IsActive DEFAULT (1),
    CreatedAt      DATETIME2(0)  NOT NULL CONSTRAINT DF_StaffUsers_CreatedAt DEFAULT (SYSUTCDATETIME())
);
GO

CREATE TABLE core.Supervisors (               -- מפקחות גנים
    SupervisorId   INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_Supervisors PRIMARY KEY,
    FullName       NVARCHAR(100) NOT NULL,
    Email          NVARCHAR(254) NULL,
    MobilePhone    CHAR(10)      NULL,
    IsActive       BIT           NOT NULL CONSTRAINT DF_Supervisors_IsActive DEFAULT (1),
    CONSTRAINT CK_Supervisors_Phone CHECK (MobilePhone IS NULL OR MobilePhone LIKE '05[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]')
);
GO

CREATE TABLE core.Suppliers (                 -- ספקים / מפעילים
    SupplierId       INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_Suppliers PRIMARY KEY,
    SupplierNumber   VARCHAR(10)   NOT NULL CONSTRAINT UQ_Suppliers_Number UNIQUE,  -- "מספר ספק" מהטבלה של דבורה, משמש גם לכניסה
    VatNumber        VARCHAR(9)    NULL,     -- מספר עוסק (רשות המסים), טרם נאסף
    Name             NVARCHAR(150) NOT NULL,
    Email            NVARCHAR(254) NULL,
    ProcySupplierId  NVARCHAR(50)  NULL,     -- פרוסי: מזהה הספק במערכת השכר (שלב ב')
    IsActive         BIT           NOT NULL CONSTRAINT DF_Suppliers_IsActive DEFAULT (1),
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_Suppliers_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_Suppliers_Number CHECK (SupplierNumber NOT LIKE '%[^0-9]%' AND LEN(SupplierNumber) BETWEEN 5 AND 10),
    CONSTRAINT CK_Suppliers_Vat    CHECK (VatNumber IS NULL OR (VatNumber NOT LIKE '%[^0-9]%' AND LEN(VatNumber) = 9)),
    CONSTRAINT CK_Suppliers_Email  CHECK (Email IS NULL OR Email LIKE '_%@_%._%')
);
CREATE UNIQUE INDEX UX_Suppliers_Procy ON core.Suppliers (ProcySupplierId) WHERE ProcySupplierId IS NOT NULL;
GO

CREATE TABLE core.SupplierContacts (          -- אנשי קשר לספק (למשל תאטרון אגדתא: אביטל ואילנית)
    ContactId      INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_SupplierContacts PRIMARY KEY,
    SupplierId     INT           NOT NULL CONSTRAINT FK_SupplierContacts_Supplier REFERENCES core.Suppliers (SupplierId),
    FullName       NVARCHAR(100) NOT NULL,
    MobilePhone    CHAR(10)      NOT NULL,   -- נייד לקוד אימות
    Email          NVARCHAR(254) NULL,
    IsPrimary      BIT           NOT NULL CONSTRAINT DF_SupplierContacts_IsPrimary DEFAULT (0),
    CanLogin       BIT           NOT NULL CONSTRAINT DF_SupplierContacts_CanLogin DEFAULT (1),
    IsActive       BIT           NOT NULL CONSTRAINT DF_SupplierContacts_IsActive DEFAULT (1),
    CONSTRAINT CK_SupplierContacts_Phone CHECK (MobilePhone LIKE '05[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]')
);
-- אותו נייד לא יכול להיות פעיל פעמיים אצל אותו ספק
CREATE UNIQUE INDEX UX_SupplierContacts_Phone ON core.SupplierContacts (SupplierId, MobilePhone) WHERE IsActive = 1;
GO

CREATE TABLE core.Kindergartens (             -- גנים
    KindergartenId   INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_Kindergartens PRIMARY KEY,
    KindergartenCode CHAR(6)       NOT NULL CONSTRAINT UQ_Kindergartens_Code UNIQUE,  -- סמל גן, 6 ספרות
    Name             NVARCHAR(100) NOT NULL,
    Address          NVARCHAR(200) NULL,
    SupervisorId     INT           NULL CONSTRAINT FK_Kindergartens_Supervisor REFERENCES core.Supervisors (SupervisorId),
    ReferentStaffUserId INT        NULL CONSTRAINT FK_Kindergartens_Referent REFERENCES core.StaffUsers (StaffUserId), -- אם רפרנטיות מחולקות לפי גנים
    IsManualTrack    BIT           NOT NULL CONSTRAINT DF_Kindergartens_Manual DEFAULT (0),  -- מסלול טופס ידני (גננת שמסרבת לחתום דיגיטלית)
    IsActive         BIT           NOT NULL CONSTRAINT DF_Kindergartens_IsActive DEFAULT (1),
    CONSTRAINT CK_Kindergartens_Code CHECK (KindergartenCode LIKE '[0-9][0-9][0-9][0-9][0-9][0-9]')
);
GO

CREATE TABLE core.Teachers (                  -- גננות (כולל ממלאות מקום)
    TeacherId      INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_Teachers PRIMARY KEY,
    FullName       NVARCHAR(100) NOT NULL,
    MobilePhone    CHAR(10)      NOT NULL,
    Email          NVARCHAR(254) NULL,
    IsActive       BIT           NOT NULL CONSTRAINT DF_Teachers_IsActive DEFAULT (1),
    CONSTRAINT CK_Teachers_Phone CHECK (MobilePhone LIKE '05[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]')
);
-- נייד מזהה גננת אחת בלבד (בסיס לקוד האימות)
CREATE UNIQUE INDEX UX_Teachers_Phone ON core.Teachers (MobilePhone) WHERE IsActive = 1;
GO

CREATE TABLE core.TeacherAssignments (        -- שיבוץ גננת לגן, עם תאריכים (מחליפות, העברות)
    AssignmentId   INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_TeacherAssignments PRIMARY KEY,
    TeacherId      INT           NOT NULL CONSTRAINT FK_TeacherAssignments_Teacher REFERENCES core.Teachers (TeacherId),
    KindergartenId INT           NOT NULL CONSTRAINT FK_TeacherAssignments_Kg REFERENCES core.Kindergartens (KindergartenId),
    ValidFrom      DATE          NOT NULL,
    ValidTo        DATE          NULL,       -- NULL = שיבוץ פעיל
    IsSubstitute   BIT           NOT NULL CONSTRAINT DF_TeacherAssignments_Sub DEFAULT (0),
    CONSTRAINT CK_TeacherAssignments_Dates CHECK (ValidTo IS NULL OR ValidTo >= ValidFrom)
);
CREATE INDEX IX_TeacherAssignments_Kg ON core.TeacherAssignments (KindergartenId, ValidFrom, ValidTo);
GO

CREATE TABLE core.SupervisorApprovals (       -- אישור מפקחת להתקשרות חד פעמית / תוספת מיתרה
    SupervisorApprovalId INT       NOT NULL IDENTITY(1,1) CONSTRAINT PK_SupervisorApprovals PRIMARY KEY,
    SupervisorId   INT           NOT NULL CONSTRAINT FK_SupervisorApprovals_Supervisor REFERENCES core.Supervisors (SupervisorId),
    ApprovedOn     DATE          NOT NULL,
    RecordedByStaffUserId INT    NOT NULL CONSTRAINT FK_SupervisorApprovals_Staff REFERENCES core.StaffUsers (StaffUserId),
    AttachmentPath NVARCHAR(400) NULL,       -- מסמך / מייל אישור סרוק
    Notes          NVARCHAR(500) NULL,
    CreatedAt      DATETIME2(0)  NOT NULL CONSTRAINT DF_SupervisorApprovals_CreatedAt DEFAULT (SYSUTCDATETIME())
);
GO

CREATE TABLE core.Engagements (               -- התקשרות: ספק x גן x שנה x פעילות (שורה בטבלה המרכזת)
    EngagementId     INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_Engagements PRIMARY KEY,
    SchoolYearId     SMALLINT      NOT NULL CONSTRAINT FK_Engagements_Year REFERENCES ref.SchoolYears (SchoolYearId),
    SupplierId       INT           NOT NULL CONSTRAINT FK_Engagements_Supplier REFERENCES core.Suppliers (SupplierId),
    KindergartenId   INT           NOT NULL CONSTRAINT FK_Engagements_Kg REFERENCES core.Kindergartens (KindergartenId),
    DomainId         SMALLINT      NOT NULL CONSTRAINT FK_Engagements_Domain REFERENCES ref.ActivityDomains (DomainId),
    EngagementTypeId TINYINT       NOT NULL CONSTRAINT FK_Engagements_Type REFERENCES ref.EngagementTypes (EngagementTypeId),
    TariffPerSession DECIMAL(10,2) NOT NULL, -- עלות למפגש לפי ההסכם
    MaxSessions      SMALLINT      NOT NULL, -- תקרת מפגשים שנתית
    AnnualBudget     DECIMAL(12,2) NOT NULL, -- תקרה כספית שנתית ("שנתי לספק")
    SupervisorApprovalId INT       NULL CONSTRAINT FK_Engagements_SupApproval REFERENCES core.SupervisorApprovals (SupervisorApprovalId),
    SourceNote       NVARCHAR(300) NULL,     -- הטקסט המקורי מעמודת "תחום הפעלה", לשקיפות
    SourceRowNumber  INT           NULL,     -- מספר השורה באקסל המקורי
    IsActive         BIT           NOT NULL CONSTRAINT DF_Engagements_IsActive DEFAULT (1),
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_Engagements_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_Engagements_Values CHECK (TariffPerSession > 0 AND MaxSessions > 0 AND AnnualBudget > 0)
);
CREATE INDEX IX_Engagements_Supplier ON core.Engagements (SupplierId, SchoolYearId) INCLUDE (KindergartenId, IsActive);
CREATE INDEX IX_Engagements_Kg       ON core.Engagements (KindergartenId, SchoolYearId) INCLUDE (SupplierId, IsActive);
GO

CREATE TABLE core.WorkOrders (                -- הזמנות עבודה (הזמנה 1, הזמנה 2...) מול ההתקשרות
    WorkOrderId      INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_WorkOrders PRIMARY KEY,
    EngagementId     INT           NOT NULL CONSTRAINT FK_WorkOrders_Engagement REFERENCES core.Engagements (EngagementId),
    OrderSeq         TINYINT       NOT NULL, -- 1, 2, ...
    Amount           DECIMAL(12,2) NOT NULL,
    OrderDate        DATE          NULL,
    ProcyOrderNumber NVARCHAR(50)  NULL,     -- פרוסי: מספר ההזמנה (שלב ב')
    Notes            NVARCHAR(300) NULL,
    CONSTRAINT UQ_WorkOrders_Seq UNIQUE (EngagementId, OrderSeq),
    CONSTRAINT CK_WorkOrders_Amount CHECK (Amount >= 0)
);
GO

CREATE TABLE core.CapOverrides (              -- אישור חריגה מתקרה על ידי רפרנטית
    CapOverrideId    INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_CapOverrides PRIMARY KEY,
    EngagementId     INT           NOT NULL CONSTRAINT FK_CapOverrides_Engagement REFERENCES core.Engagements (EngagementId),
    ExtraSessions    SMALLINT      NULL,     -- כמה מפגשים נוספים אושרו
    ExtraAmount      DECIMAL(12,2) NULL,     -- כמה כסף נוסף אושר
    Reason           NVARCHAR(500) NOT NULL,
    ApprovedByStaffUserId INT      NOT NULL CONSTRAINT FK_CapOverrides_Staff REFERENCES core.StaffUsers (StaffUserId),
    ApprovedAt       DATETIME2(0)  NOT NULL CONSTRAINT DF_CapOverrides_ApprovedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_CapOverrides_Something CHECK (ISNULL(ExtraSessions,0) > 0 OR ISNULL(ExtraAmount,0) > 0)
);
GO

/* =====================================================================
   ops.Notifications (יומן הודעות) + auth : קודי אימות ונעילה
   ===================================================================== */

CREATE TABLE ops.Notifications (              -- יומן כל SMS / שיחה / מייל, כולל תזכורות מתוזמנות
    NotificationId   BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_Notifications PRIMARY KEY,
    Channel          VARCHAR(10)   NOT NULL, -- SMS | VOICE | EMAIL
    Purpose          VARCHAR(20)   NOT NULL, -- OTP | APPROVAL_REQUEST | REMINDER | ESCALATION | CAP_WARNING
    RecipientType    VARCHAR(20)   NOT NULL, -- TEACHER | SUPPLIER_CONTACT | STAFF
    RecipientId      INT           NOT NULL,
    Destination      NVARCHAR(254) NOT NULL, -- מספר / מייל בפועל
    ReportId         INT           NULL,
    ScheduledFor     DATETIME2(0)  NOT NULL CONSTRAINT DF_Notifications_Scheduled DEFAULT (SYSUTCDATETIME()),
    SentAt           DATETIME2(0)  NULL,
    Status           VARCHAR(12)   NOT NULL CONSTRAINT DF_Notifications_Status DEFAULT ('QUEUED'),
    ProviderMessageId NVARCHAR(100) NULL,    -- מזהה ההודעה אצל ספק ה-SMS (mgroup)
    ErrorText        NVARCHAR(500) NULL,
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_Notifications_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_Notifications_Channel CHECK (Channel IN ('SMS','VOICE','EMAIL')),
    CONSTRAINT CK_Notifications_Purpose CHECK (Purpose IN ('OTP','APPROVAL_REQUEST','REMINDER','ESCALATION','CAP_WARNING')),
    CONSTRAINT CK_Notifications_Recipient CHECK (RecipientType IN ('TEACHER','SUPPLIER_CONTACT','STAFF')),
    CONSTRAINT CK_Notifications_Status CHECK (Status IN ('QUEUED','SENT','DELIVERED','FAILED','CANCELLED'))
);
CREATE INDEX IX_Notifications_Queue ON ops.Notifications (Status, ScheduledFor);
CREATE INDEX IX_Notifications_Dest  ON ops.Notifications (Destination, CreatedAt);  -- הגבלת קצב שליחה לנייד
GO

CREATE TABLE auth.OtpRequests (               -- קוד אימות: נשמר מוצפן, לעולם לא כטקסט
    OtpRequestId     BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_OtpRequests PRIMARY KEY,
    UserType         VARCHAR(20)   NOT NULL, -- TEACHER | SUPPLIER_CONTACT
    UserId           INT           NOT NULL, -- TeacherId או ContactId
    LoginKey         VARCHAR(10)   NOT NULL, -- סמל הגן או מספר הספק שהוזן
    MobilePhone      CHAR(10)      NOT NULL, -- הנייד שנבחר מהרשימה המוסתרת
    Channel          VARCHAR(10)   NOT NULL, -- SMS | VOICE
    CodeHash         VARBINARY(32) NOT NULL, -- SHA-256 של הקוד + Salt
    CodeSalt         VARBINARY(16) NOT NULL,
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_OtpRequests_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ExpiresAt        DATETIME2(0)  NOT NULL, -- CreatedAt + OtpTtlMinutes (5)
    AttemptCount     TINYINT       NOT NULL CONSTRAINT DF_OtpRequests_Attempts DEFAULT (0),
    ConsumedAt       DATETIME2(0)  NULL,     -- הוזן נכון
    NotificationId   BIGINT        NULL CONSTRAINT FK_OtpRequests_Notification REFERENCES ops.Notifications (NotificationId),
    CONSTRAINT CK_OtpRequests_UserType CHECK (UserType IN ('TEACHER','SUPPLIER_CONTACT')),
    CONSTRAINT CK_OtpRequests_Channel  CHECK (Channel IN ('SMS','VOICE')),
    CONSTRAINT CK_OtpRequests_Expiry   CHECK (ExpiresAt > CreatedAt)
);
CREATE INDEX IX_OtpRequests_Phone ON auth.OtpRequests (MobilePhone, CreatedAt DESC);
GO

CREATE TABLE auth.PhoneLockouts (             -- נעילה לפי נייד (לא לפי גן / ספק)
    MobilePhone      CHAR(10)      NOT NULL CONSTRAINT PK_PhoneLockouts PRIMARY KEY,
    FailedAttempts   TINYINT       NOT NULL CONSTRAINT DF_PhoneLockouts_Failed DEFAULT (0),
    LastFailedAt     DATETIME2(0)  NULL,
    LockedUntil      DATETIME2(0)  NULL      -- NULL או עבר = לא נעול
);
GO

/* =====================================================================
   ops : דיווחים ואישורים
   ===================================================================== */

CREATE TABLE ops.Reports (                    -- דיווח חודשי: התקשרות אחת, חודש אחד
    ReportId         INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_Reports PRIMARY KEY,
    EngagementId     INT           NOT NULL CONSTRAINT FK_Reports_Engagement REFERENCES core.Engagements (EngagementId),
    ReportYear       SMALLINT      NOT NULL,
    ReportMonth      TINYINT       NOT NULL,
    StatusId         TINYINT       NOT NULL CONSTRAINT FK_Reports_Status REFERENCES ref.ReportStatuses (StatusId),
    SubmittedByContactId INT       NULL CONSTRAINT FK_Reports_Contact REFERENCES core.SupplierContacts (ContactId),
    SubmittedAt      DATETIME2(0)  NULL,
    IsManual         BIT           NOT NULL CONSTRAINT DF_Reports_IsManual DEFAULT (0),  -- הוזן ידנית ע"י הצוות (מסלול ידני)
    ManualScanPath   NVARCHAR(400) NULL,     -- סריקת הטופס הידני
    EnteredByStaffUserId INT       NULL CONSTRAINT FK_Reports_EnteredBy REFERENCES core.StaffUsers (StaffUserId),
    FinalApprovedByStaffUserId INT NULL CONSTRAINT FK_Reports_ApprovedBy REFERENCES core.StaffUsers (StaffUserId),
    FinalApprovedAt  DATETIME2(0)  NULL,
    LockedAt         DATETIME2(0)  NULL,
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_Reports_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_Reports_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    RowVer           ROWVERSION,             -- מניעת דריסה בעריכה מקבילית
    CONSTRAINT UQ_Reports_EngagementMonth UNIQUE (EngagementId, ReportYear, ReportMonth),
    CONSTRAINT UQ_Reports_IdEngagement    UNIQUE (ReportId, EngagementId),  -- עבור FK מורכב משורות הדיווח
    CONSTRAINT CK_Reports_Month  CHECK (ReportMonth BETWEEN 1 AND 12),
    CONSTRAINT CK_Reports_Year   CHECK (ReportYear BETWEEN 2024 AND 2100),
    CONSTRAINT CK_Reports_Manual CHECK (IsManual = 0 OR EnteredByStaffUserId IS NOT NULL)
);
CREATE INDEX IX_Reports_Period ON ops.Reports (ReportYear, ReportMonth, StatusId);
GO

ALTER TABLE ops.Notifications ADD CONSTRAINT FK_Notifications_Report FOREIGN KEY (ReportId) REFERENCES ops.Reports (ReportId);
GO

CREATE TABLE ops.ReportLines (                -- שורה לכל תאריך ביקור
    ReportLineId     INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_ReportLines PRIMARY KEY,
    ReportId         INT           NOT NULL,
    EngagementId     INT           NOT NULL, -- משוכפל מהדיווח כדי לאכוף "אין אותו תאריך פעמיים" בין חודשים
    VisitDate        DATE          NOT NULL,
    SessionTypeId    TINYINT       NOT NULL CONSTRAINT FK_ReportLines_SessionType REFERENCES ref.SessionTypes (SessionTypeId),
    TariffApplied    DECIMAL(10,2) NOT NULL, -- צילום התעריף ביום הדיווח (לא משתנה אם החוזה יעודכן)
    PayMultiplier    DECIMAL(4,2)  NOT NULL, -- צילום מ-SessionTypes
    CapUnits         TINYINT       NOT NULL, -- צילום מ-SessionTypes
    LineAmount       AS CAST(TariffApplied * PayMultiplier AS DECIMAL(12,2)) PERSISTED,
    IsHolidayFlag    BIT           NOT NULL CONSTRAINT DF_ReportLines_Holiday DEFAULT (0),  -- ביקור בחג / שבת
    IsOverCapFlag    BIT           NOT NULL CONSTRAINT DF_ReportLines_OverCap DEFAULT (0),  -- נכנס רק באישור חריגה
    Notes            NVARCHAR(300) NULL,
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_ReportLines_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_ReportLines_Report FOREIGN KEY (ReportId, EngagementId) REFERENCES ops.Reports (ReportId, EngagementId),
    -- חסימת כפילות: אותו תאריך לאותה התקשרות פעם אחת בלבד (גם בין חודשים). שיעור כפול = SessionType, לא שורה נוספת
    CONSTRAINT UQ_ReportLines_EngagementDate UNIQUE (EngagementId, VisitDate),
    CONSTRAINT CK_ReportLines_Values CHECK (TariffApplied > 0 AND PayMultiplier > 0)
);
CREATE INDEX IX_ReportLines_Report ON ops.ReportLines (ReportId);
GO

CREATE TABLE ops.ReportStatusHistory (        -- כל מעבר סטטוס, עם מי ומתי
    HistoryId        BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_ReportStatusHistory PRIMARY KEY,
    ReportId         INT           NOT NULL CONSTRAINT FK_ReportStatusHistory_Report REFERENCES ops.Reports (ReportId),
    FromStatusId     TINYINT       NULL CONSTRAINT FK_ReportStatusHistory_From REFERENCES ref.ReportStatuses (StatusId),
    ToStatusId       TINYINT       NOT NULL CONSTRAINT FK_ReportStatusHistory_To REFERENCES ref.ReportStatuses (StatusId),
    ChangedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_ReportStatusHistory_At DEFAULT (SYSUTCDATETIME()),
    ActorType        VARCHAR(20)   NOT NULL, -- SUPPLIER_CONTACT | TEACHER | STAFF | SYSTEM
    ActorId          INT           NULL,
    RejectionReasonId TINYINT      NULL CONSTRAINT FK_ReportStatusHistory_Reason REFERENCES ref.RejectionReasons (RejectionReasonId),
    Comment          NVARCHAR(500) NULL,
    CONSTRAINT CK_ReportStatusHistory_Actor CHECK (ActorType IN ('SUPPLIER_CONTACT','TEACHER','STAFF','SYSTEM'))
);
CREATE INDEX IX_ReportStatusHistory_Report ON ops.ReportStatusHistory (ReportId, ChangedAt);
GO

CREATE TABLE ops.TeacherApprovals (           -- ראיה לחתימה דיגיטלית של הגננת
    TeacherApprovalId BIGINT       NOT NULL IDENTITY(1,1) CONSTRAINT PK_TeacherApprovals PRIMARY KEY,
    ReportId         INT           NOT NULL CONSTRAINT FK_TeacherApprovals_Report REFERENCES ops.Reports (ReportId),
    TeacherId        INT           NOT NULL CONSTRAINT FK_TeacherApprovals_Teacher REFERENCES core.Teachers (TeacherId),
    Decision         VARCHAR(10)   NOT NULL, -- APPROVED | REJECTED
    DecidedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_TeacherApprovals_At DEFAULT (SYSUTCDATETIME()),
    OtpRequestId     BIGINT        NOT NULL CONSTRAINT FK_TeacherApprovals_Otp REFERENCES auth.OtpRequests (OtpRequestId),
    PhoneUsed        CHAR(10)      NOT NULL,
    IpAddress        VARCHAR(45)   NULL,
    UserAgent        NVARCHAR(400) NULL,
    ContentHash      VARBINARY(32) NOT NULL, -- SHA-256 של תוכן הדיווח שאושר. שינוי אחרי האישור = אי התאמה
    RejectionReasonId TINYINT      NULL CONSTRAINT FK_TeacherApprovals_Reason REFERENCES ref.RejectionReasons (RejectionReasonId),
    Comment          NVARCHAR(500) NULL,
    CONSTRAINT CK_TeacherApprovals_Decision CHECK (Decision IN ('APPROVED','REJECTED')),
    CONSTRAINT CK_TeacherApprovals_Reason   CHECK (Decision = 'APPROVED' OR RejectionReasonId IS NOT NULL)
);
CREATE INDEX IX_TeacherApprovals_Report ON ops.TeacherApprovals (ReportId, DecidedAt);
GO

/* =====================================================================
   audit : יומן פעולות
   ===================================================================== */

CREATE TABLE audit.ActionLog (
    ActionLogId      BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_ActionLog PRIMARY KEY,
    OccurredAt       DATETIME2(0)  NOT NULL CONSTRAINT DF_ActionLog_At DEFAULT (SYSUTCDATETIME()),
    ActorType        VARCHAR(20)   NOT NULL, -- SUPPLIER_CONTACT | TEACHER | STAFF | SYSTEM | ANONYMOUS
    ActorId          INT           NULL,
    Action           VARCHAR(50)   NOT NULL, -- LOGIN_OK, LOGIN_FAILED, OTP_SENT, REPORT_SUBMITTED, CAP_OVERRIDE ...
    EntityName       VARCHAR(50)   NULL,
    EntityId         BIGINT        NULL,
    Details          NVARCHAR(MAX) NULL,     -- JSON
    IpAddress        VARCHAR(45)   NULL
);
CREATE INDEX IX_ActionLog_Entity ON audit.ActionLog (EntityName, EntityId);
CREATE INDEX IX_ActionLog_At     ON audit.ActionLog (OccurredAt);
GO

/* =====================================================================
   procy : תשתית לחיבור לפרוסי (שלב ב'). נבנית עכשיו, ריקה עד החיבור.
   ===================================================================== */

CREATE TABLE procy.ExportBatches (            -- אצוות ייצוא חודשית
    ExportBatchId    INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_ExportBatches PRIMARY KEY,
    PeriodYear       SMALLINT      NOT NULL,
    PeriodMonth      TINYINT       NOT NULL,
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_ExportBatches_At DEFAULT (SYSUTCDATETIME()),
    CreatedByStaffUserId INT       NULL CONSTRAINT FK_ExportBatches_Staff REFERENCES core.StaffUsers (StaffUserId),
    Status           VARCHAR(12)   NOT NULL CONSTRAINT DF_ExportBatches_Status DEFAULT ('OPEN'),
    FileName         NVARCHAR(200) NULL,     -- אם הייצוא יהיה קובץ
    LineCount        INT           NULL,
    TotalAmount      DECIMAL(14,2) NULL,
    CONSTRAINT CK_ExportBatches_Status CHECK (Status IN ('OPEN','SENT','ACKED','FAILED')),
    CONSTRAINT CK_ExportBatches_Month  CHECK (PeriodMonth BETWEEN 1 AND 12)
);
GO

CREATE TABLE procy.Outbox (                   -- תור ייצוא: כל דיווח שננעל נכנס לכאן אוטומטית
    OutboxId         BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_Outbox PRIMARY KEY,
    ReportId         INT           NOT NULL CONSTRAINT FK_Outbox_Report REFERENCES ops.Reports (ReportId),
    ExportBatchId    INT           NULL CONSTRAINT FK_Outbox_Batch REFERENCES procy.ExportBatches (ExportBatchId),
    Payload          NVARCHAR(MAX) NOT NULL, -- JSON: צילום הנתונים ברגע הנעילה
    Status           VARCHAR(12)   NOT NULL CONSTRAINT DF_Outbox_Status DEFAULT ('PENDING'),
    Attempts         TINYINT       NOT NULL CONSTRAINT DF_Outbox_Attempts DEFAULT (0),
    CreatedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_Outbox_At DEFAULT (SYSUTCDATETIME()),
    SentAt           DATETIME2(0)  NULL,
    AckAt            DATETIME2(0)  NULL,
    ProcyReference   NVARCHAR(100) NULL,     -- אסמכתא שפרוסי מחזירה
    ErrorText        NVARCHAR(1000) NULL,
    CONSTRAINT CK_Outbox_Status  CHECK (Status IN ('PENDING','SENT','ACKED','FAILED','SKIPPED')),
    CONSTRAINT CK_Outbox_Payload CHECK (ISJSON(Payload) = 1)
);
-- דיווח נכנס לתור פעם אחת בלבד, אלא אם הייצוא הקודם נכשל
CREATE UNIQUE INDEX UX_Outbox_Report ON procy.Outbox (ReportId) WHERE Status <> 'FAILED';
CREATE INDEX IX_Outbox_Pending ON procy.Outbox (Status, CreatedAt);
GO

/* =====================================================================
   stg : ייבוא
   ===================================================================== */

CREATE TABLE stg.ImportBatches (
    ImportBatchId    INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_ImportBatches PRIMARY KEY,
    SourceFiles      NVARCHAR(500) NOT NULL,
    ImportedAt       DATETIME2(0)  NOT NULL CONSTRAINT DF_ImportBatches_At DEFAULT (SYSUTCDATETIME()),
    ImportedBy       NVARCHAR(100) NULL,
    RowsRead         INT           NOT NULL,
    RowsAccepted     INT           NOT NULL,
    RowsRejected     INT           NOT NULL
);
GO

CREATE TABLE stg.RejectedRows (               -- כל שורה שלא נכנסה, עם סיבה (אותו תוכן כמו קובץ האקסל לצופיה)
    RejectedRowId    INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_RejectedRows PRIMARY KEY,
    ImportBatchId    INT           NOT NULL CONSTRAINT FK_RejectedRows_Batch REFERENCES stg.ImportBatches (ImportBatchId),
    SourceFile       NVARCHAR(200) NOT NULL,
    SourceRowNumber  INT           NOT NULL,
    Entity           NVARCHAR(30)  NOT NULL, -- גן / גננת / ספק / איש קשר / התקשרות / הזמנה
    Reason           NVARCHAR(300) NOT NULL,
    RawValues        NVARCHAR(MAX) NULL
);
GO

/* =====================================================================
   תצוגות
   ===================================================================== */

-- ניצול התקרות לכל התקשרות: מפגשים, כסף, התראה וחסימה
CREATE VIEW core.vw_EngagementUsage
AS
WITH Used AS (
    SELECT  r.EngagementId,
            SUM(CAST(l.CapUnits AS INT))  AS SessionsUsed,
            SUM(l.LineAmount)             AS AmountUsed
    FROM    ops.Reports r
    JOIN    ops.ReportLines l ON l.ReportId = r.ReportId
    JOIN    ref.ReportStatuses s ON s.StatusId = r.StatusId
    WHERE   s.Code <> 'TEACHER_REJECTED'          -- דיווח שנדחה לא נספר
    GROUP BY r.EngagementId
), Overrides AS (
    SELECT  EngagementId,
            SUM(ISNULL(ExtraSessions,0)) AS ExtraSessions,
            SUM(ISNULL(ExtraAmount,0))   AS ExtraAmount
    FROM    core.CapOverrides
    GROUP BY EngagementId
), Cfg AS (   -- שורה אחת תמיד, גם אם ההגדרה חסרה (ברירת מחדל 3)
    SELECT ISNULL(MAX(TRY_CAST(SettingValue AS INT)), 3) AS WarnRemaining
    FROM   ref.Settings WHERE SettingKey = 'CapWarnRemainingSessions'
)
SELECT  e.EngagementId,
        e.SupplierId,
        e.KindergartenId,
        e.SchoolYearId,
        e.TariffPerSession,
        e.MaxSessions  + ISNULL(o.ExtraSessions,0)   AS SessionCap,
        e.AnnualBudget + ISNULL(o.ExtraAmount,0)     AS AmountCap,
        ISNULL(u.SessionsUsed,0)                     AS SessionsUsed,
        ISNULL(u.AmountUsed,0)                       AS AmountUsed,
        e.MaxSessions  + ISNULL(o.ExtraSessions,0) - ISNULL(u.SessionsUsed,0) AS SessionsRemaining,
        e.AnnualBudget + ISNULL(o.ExtraAmount,0)   - ISNULL(u.AmountUsed,0)   AS AmountRemaining,
        -- התראה: נותרו 3 מפגשים או פחות, או נותר סכום של 3 מפגשים רגילים או פחות
        CAST(CASE WHEN e.MaxSessions + ISNULL(o.ExtraSessions,0) - ISNULL(u.SessionsUsed,0) <= c.WarnRemaining
                    OR e.AnnualBudget + ISNULL(o.ExtraAmount,0) - ISNULL(u.AmountUsed,0) <= e.TariffPerSession * c.WarnRemaining
                  THEN 1 ELSE 0 END AS BIT)          AS IsWarning,
        -- חסימה: הגיע לתקרת מפגשים או לתקרת כסף
        CAST(CASE WHEN e.MaxSessions + ISNULL(o.ExtraSessions,0) - ISNULL(u.SessionsUsed,0) <= 0
                    OR e.AnnualBudget + ISNULL(o.ExtraAmount,0) - ISNULL(u.AmountUsed,0) <= 0
                  THEN 1 ELSE 0 END AS BIT)          AS IsBlocked
FROM    core.Engagements e
CROSS JOIN Cfg c
LEFT JOIN Used u      ON u.EngagementId = e.EngagementId
LEFT JOIN Overrides o ON o.EngagementId = e.EngagementId;
GO

-- הגננות הפעילות של גן, עם נייד מוסתר לבחירה במסך הכניסה
CREATE VIEW core.vw_KindergartenLoginPhones
AS
SELECT  k.KindergartenCode,
        t.TeacherId,
        t.FullName,
        LEFT(t.MobilePhone,3) + '-***' + RIGHT(t.MobilePhone,4) AS MaskedPhone,
        COUNT(*) OVER (PARTITION BY k.KindergartenId)            AS TeachersInKg   -- 1 = לדלג על שלב הבחירה
FROM    core.Kindergartens k
JOIN    core.TeacherAssignments a ON a.KindergartenId = k.KindergartenId
JOIN    core.Teachers t           ON t.TeacherId = a.TeacherId
WHERE   k.IsActive = 1 AND t.IsActive = 1
  AND   a.ValidFrom <= CAST(SYSUTCDATETIME() AS DATE)
  AND  (a.ValidTo IS NULL OR a.ValidTo >= CAST(SYSUTCDATETIME() AS DATE));
GO

-- אנשי הקשר הפעילים של ספק, עם נייד מוסתר לבחירה במסך הכניסה
CREATE VIEW core.vw_SupplierLoginPhones
AS
SELECT  s.SupplierNumber,
        c.ContactId,
        c.FullName,
        LEFT(c.MobilePhone,3) + '-***' + RIGHT(c.MobilePhone,4) AS MaskedPhone,
        COUNT(*) OVER (PARTITION BY s.SupplierId)                AS ContactsForSupplier
FROM    core.Suppliers s
JOIN    core.SupplierContacts c ON c.SupplierId = s.SupplierId
WHERE   s.IsActive = 1 AND c.IsActive = 1 AND c.CanLogin = 1;
GO

-- החוזה לפרוסי: מה ייצא עבור כל דיווח נעול. המבנה הזה הוא נקודת המוצא לאפיון החיבור בשלב ב'
CREATE VIEW procy.vw_ReportsForExport
AS
SELECT  r.ReportId,
        r.ReportYear,
        r.ReportMonth,
        s.SupplierNumber,
        s.VatNumber,
        s.ProcySupplierId,
        k.KindergartenCode,
        y.HebrewName                       AS SchoolYear,
        et.Code                            AS EngagementType,
        d.NameHe                           AS Domain,
        COUNT(l.ReportLineId)              AS VisitCount,
        SUM(CAST(l.CapUnits AS INT))       AS SessionUnits,
        SUM(l.LineAmount)                  AS TotalAmount,
        (SELECT TOP 1 w.ProcyOrderNumber
           FROM core.WorkOrders w
          WHERE w.EngagementId = e.EngagementId AND w.ProcyOrderNumber IS NOT NULL
          ORDER BY w.OrderSeq DESC)         AS ProcyOrderNumber,
        r.LockedAt
FROM    ops.Reports r
JOIN    ref.ReportStatuses st   ON st.StatusId = r.StatusId AND st.Code = 'LOCKED'
JOIN    core.Engagements e      ON e.EngagementId = r.EngagementId
JOIN    core.Suppliers s        ON s.SupplierId = e.SupplierId
JOIN    core.Kindergartens k    ON k.KindergartenId = e.KindergartenId
JOIN    ref.SchoolYears y       ON y.SchoolYearId = e.SchoolYearId
JOIN    ref.EngagementTypes et  ON et.EngagementTypeId = e.EngagementTypeId
JOIN    ref.ActivityDomains d   ON d.DomainId = e.DomainId
JOIN    ops.ReportLines l       ON l.ReportId = r.ReportId
GROUP BY r.ReportId, r.ReportYear, r.ReportMonth, s.SupplierNumber, s.VatNumber, s.ProcySupplierId,
         k.KindergartenCode, y.HebrewName, et.Code, d.NameHe, e.EngagementId, r.LockedAt;
GO

/* =====================================================================
   טריגר: כל דיווח שעובר לסטטוס LOCKED נכנס אוטומטית לתור הייצוא לפרוסי
   ===================================================================== */
CREATE TRIGGER ops.trg_Reports_EnqueueProcy
ON ops.Reports
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(StatusId) RETURN;

    INSERT INTO procy.Outbox (ReportId, Payload)
    SELECT  i.ReportId,
            (SELECT v.* FROM procy.vw_ReportsForExport v
              WHERE v.ReportId = i.ReportId
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM    inserted i
    JOIN    deleted  d  ON d.ReportId = i.ReportId
    JOIN    ref.ReportStatuses s ON s.StatusId = i.StatusId AND s.Code = 'LOCKED'
    WHERE   i.StatusId <> d.StatusId
      AND   NOT EXISTS (SELECT 1 FROM procy.Outbox o WHERE o.ReportId = i.ReportId AND o.Status <> 'FAILED')
      AND   EXISTS (SELECT 1 FROM procy.vw_ReportsForExport v WHERE v.ReportId = i.ReportId);
END;
GO

PRINT N'01_create_schema.sql הושלם';
GO
