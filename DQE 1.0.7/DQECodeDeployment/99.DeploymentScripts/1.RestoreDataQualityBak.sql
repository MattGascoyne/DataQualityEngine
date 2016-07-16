USE [master]

--SELECT 'X'
SELECT '$(deploymentPath)'
SELECT '$(dbFilePath)'
SELECT '$(dbLogPath)'
--SELECT 'Y'

RESTORE DATABASE [DataQualityDB] 
FROM  DISK = N'$(deploymentPath)\DataQualityDB.bak'
WITH FILE = 1,  
MOVE N'DataQualityDB' TO N'$(dbFilePath)\DataQualityDB.mdf',  
MOVE N'DataQualityDB_log' TO N'$(dbLogPath)\DataQualityDB_log.ldf',  
NOUNLOAD,  REPLACE,  STATS = 5
GO


