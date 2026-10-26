/* =====================================================================
   02_enable_history.sql  |  שלב א'
   היסטוריית שינויים אוטומטית (System-Versioned Temporal Tables)
   ---------------------------------------------------------------------
   כל שינוי בטבלאות האלה נשמר אוטומטית בטבלת היסטוריה במקביל:
   מי שינה תעריף, מתי, ומה היה הערך הקודם.
   דורש SQL Server 2016 ומעלה. אם הגרסה ישנה יותר, לדלג על הקובץ הזה
   (המערכת תעבוד, רק בלי היסטוריה אוטומטית).

   דוגמה לשאילתה: מה היה התעריף של התקשרות 15 ב-1 בינואר?
   SELECT * FROM core.Engagements FOR SYSTEM_TIME AS OF '2026-01-01' WHERE EngagementId = 15;
   ===================================================================== */

SET NOCOUNT ON;
GO

IF SCHEMA_ID(N'history') IS NULL EXEC(N'CREATE SCHEMA history');
GO

DECLARE @tables TABLE (SchemaName SYSNAME, TableName SYSNAME);
INSERT INTO @tables VALUES
    (N'core', N'Suppliers'),
    (N'core', N'SupplierContacts'),
    (N'core', N'Kindergartens'),
    (N'core', N'Teachers'),
    (N'core', N'TeacherAssignments'),
    (N'core', N'Engagements'),
    (N'core', N'WorkOrders'),
    (N'ref',  N'Settings');

DECLARE @s SYSNAME, @t SYSNAME, @sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT SchemaName, TableName FROM @tables;
OPEN c;
FETCH NEXT FROM c INTO @s, @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID(QUOTENAME(@s) + N'.' + QUOTENAME(@t)) AND temporal_type = 2)
    BEGIN
        SET @sql = N'
ALTER TABLE ' + QUOTENAME(@s) + N'.' + QUOTENAME(@t) + N' ADD
    ValidFromUtc DATETIME2(0) GENERATED ALWAYS AS ROW START HIDDEN
        CONSTRAINT ' + QUOTENAME(N'DF_' + @t + N'_ValidFromUtc') + N' DEFAULT (SYSUTCDATETIME()),
    ValidToUtc   DATETIME2(0) GENERATED ALWAYS AS ROW END HIDDEN
        CONSTRAINT ' + QUOTENAME(N'DF_' + @t + N'_ValidToUtc') + N' DEFAULT (CONVERT(DATETIME2(0), ''9999-12-31 23:59:59'')),
    PERIOD FOR SYSTEM_TIME (ValidFromUtc, ValidToUtc);
ALTER TABLE ' + QUOTENAME(@s) + N'.' + QUOTENAME(@t) + N'
    SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = history.' + QUOTENAME(@s + N'_' + @t) + N'));';
        EXEC sys.sp_executesql @sql;
        PRINT N'היסטוריה הופעלה: ' + @s + N'.' + @t;
    END
    FETCH NEXT FROM c INTO @s, @t;
END
CLOSE c; DEALLOCATE c;
GO

PRINT N'02_enable_history.sql הושלם';
GO
