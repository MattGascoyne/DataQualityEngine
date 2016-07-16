USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'fnGetParameterValue'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP FUNCTION [DQ].[fnGetParameterValue]
END

GO


CREATE FUNCTION [DQ].[fnGetParameterValue] 
(
@ParameterName VARCHAR (255))
RETURNS VARCHAR (255)

BEGIN
	DECLARE @ParameterValue VARCHAR (255)
	SELECT @ParameterValue = Value
	FROM MDS.DQAppParameters
	WHERE Name = @ParameterName
	RETURN @ParameterValue
END


GO

