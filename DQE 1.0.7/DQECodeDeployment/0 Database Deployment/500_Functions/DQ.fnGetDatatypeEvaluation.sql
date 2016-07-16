USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'fnGetDatatypeEvaluation'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP FUNCTION [DQ].[fnGetDatatypeEvaluation]
END

GO

CREATE FUNCTION [DQ].[fnGetDatatypeEvaluation]
(
@dataTypeFirst varchar(32),
@dataTypeSecond varchar(32)
)
RETURNS VARCHAR(32)

BEGIN
DECLARE @conversionAction varchar(32)

SELECT 
	@conversionAction = conversionActionType_Name
FROM 
	[MDS].[DQAppDataTypeConversion] 
WHERE 
	SourceDataType_Name = @dataTypeFirst AND DestinationDataType_Name = @dataTypeSecond

RETURN @conversionAction
END

GO
