USE DataQualityDB
go

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'fnRemoveMCharacters'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP FUNCTION [DQ].[fnRemoveMCharacters]
END

GO

	create Function [DQ].[fnRemoveMCharacters](@String VarChar(1000))
	Returns VarChar(1000)
	AS
	Begin
		SET @string = replace (@string, 'M', '')

		Return @String
	End