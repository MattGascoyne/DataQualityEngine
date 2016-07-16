USE Master
go

IF EXISTS (select 1 from sys.databases where name = 'DataQualityDB')
BEGIN
	ALTER DATABASE DataQualityDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE
	DROP DATABASE DataQualityDB
END
go


