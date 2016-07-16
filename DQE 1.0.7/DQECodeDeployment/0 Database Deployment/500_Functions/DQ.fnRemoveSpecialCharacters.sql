use DataQualityDB
go

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'fnRemoveSpecialCharacters'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP FUNCTION [DQ].[fnRemoveSpecialCharacters]
END

GO

	CREATE Function [DQ].[fnRemoveSpecialCharacters](@String VarChar(1000))
	Returns VarChar(1000)
	AS
	Begin

	  declare @i int = 1;  -- must start from 1, as SubString is 1-based
	  declare @OriginalString varchar(1000) = @String Collate SQL_Latin1_General_CP1253_CI_AI;
	  declare @ModifiedString varchar(1000) = '';

	  while @i <= Len(@OriginalString)
	  begin
		if SubString(@OriginalString, @i, 1) like '[a-Z]'
		begin
		  set @ModifiedString = @ModifiedString + SubString(@OriginalString, @i, 1);
		end
		set @i = @i + 1;
	  end

	  return @ModifiedString

	end