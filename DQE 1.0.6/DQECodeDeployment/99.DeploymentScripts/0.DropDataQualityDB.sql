USE Master
go

IF EXISTS (select 1 from sys.databases where name = 'DataQualityDB')
BEGIN
DROP Database DataQualityDB
END
go


