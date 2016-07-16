use DataQualityDB
go

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'fnGetSeverityCode'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP FUNCTION [DQ].[fnGetSeverityCode]
END

GO


CREATE FUNCTION [DQ].[fnGetSeverityCode] 
(
@ParameterName VARCHAR (255))
RETURNS VARCHAR (255)

BEGIN
	DECLARE @ParameterValue VARCHAR (255)
	SELECT @ParameterValue = Code
	FROM [MDS].[DQAppSeverity]
	WHERE Name = @ParameterName
	RETURN @ParameterValue
END


GO

