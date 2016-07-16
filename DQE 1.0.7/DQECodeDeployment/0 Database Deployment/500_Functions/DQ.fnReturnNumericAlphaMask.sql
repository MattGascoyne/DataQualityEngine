use DataQualityDB
go

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'fnReturnNumericAlphaMask'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP FUNCTION [DQ].[fnReturnNumericAlphaMask]
END

GO

CREATE Function [DQ].[fnReturnNumericAlphaMask](@String VarChar(1000))
	Returns VarChar(1000)
		/******************************************************************************
	**	Author:			Matt Gascoyne
	**	Created Date:	10/05/2016
	**	Approx RunTime:
	**	Desc:			Function to get the Alpha and Numeric patterns. Ideal for checking a standard pattern is adhered to.
	**	Examples:		Input: 14A --> Output: NNA
	**					Input: 14A/21 --> Output: NNA/NN
	**					
	**
	**	Return values: Success Status
	** 
	**	Called by: 
	**              
	**	Parameters:
	**	Input
	**	----------
	**	String
	**
	**	Output
	**	----------
	**	Varchar 
	**  
	*******************************************************************************
	**	Change History
	*******************************************************************************
	**	By:	Date:		Description:
	**	---	--------	-----------------------------------------------------------
	**     MG     01/03/2016    Release 1.0.3	
	******************************************************************************/
	
	AS
	BEGIN


	  DECLARE @i INT = 1;  
	  DECLARE @OriginalString VARCHAR(1000) = @String Collate SQL_Latin1_General_CP1253_CI_AI;
	  DECLARE @ModifiedString VARCHAR(1000) = '';

	  IF @OriginalString IS NULL
		BEGIN
			SET @ModifiedString = 'NULL'
		END	
	  ELSE IF LEN (@OriginalString) = 0
		BEGIN
			SET @ModifiedString = 'Blank'
		END	

	  ELSE
	  BEGIN
		  WHILE @i <= Len(@OriginalString)
		  BEGIN
			IF SubString(@OriginalString, @i, 1) like '[a-Z]'
			BEGIN
			  SET @ModifiedString = @ModifiedString + 'A';
			END
			ELSE IF SubString(@OriginalString, @i, 1) like '[0-9]'
			BEGIN
			  SET @ModifiedString = @ModifiedString + 'N';
			END
			ELSE 
			BEGIN
			  SET @ModifiedString = @ModifiedString + + SubString(@OriginalString, @i, 1);;
			END
			SET @i = @i + 1;
		  END
		END

	  RETURN @ModifiedString

	END
GO


