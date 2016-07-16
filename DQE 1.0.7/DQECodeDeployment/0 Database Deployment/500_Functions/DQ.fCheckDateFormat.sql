USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'fCheckDateFormat'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP FUNCTION [DQ].[fCheckDateFormat]
END

GO


/*

SELECT [DQ].[fCheckStringFormat] ('2/2/16', 'dd/mm/YY')

SELECT [DQ].[fCheckStringFormat] ('20160230', 'YYYYMMDD')

*/

CREATE FUNCTION [DQ].[fCheckDateFormat](@StringValue VARCHAR(2000), @Pattern VARCHAR(2000))
RETURNS INT
/******************************************************************************
**	Author:			 Dartec Systems (Matt Gascoyne)
**	Created Date:	26/04/2016
**	Approx RunTime:
**	Desc:			Generic function to return a value based on a pattern
**					
**
**	Return values: Success Status
** 
**	Called by: 
**              
**	Parameters:
**	Input
**	----------
**
**	Output
**	----------
**  
*******************************************************************************
**	Change History
*******************************************************************************
**	By:	Date:		Description:
**	---	--------	-----------------------------------------------------------
**     MG     01/03/2016    Release 1.0.3	

*******************************************************************************/


BEGIN
	--DECLARE @StringValue VARCHAR(2000) = '31/12/2016'
	--DECLARE @Pattern VARCHAR(2000) = 'DD/MM/YYYY'
	/*______________________________________________
	**Declare Local Variables
	**______________________________________________*/
	DECLARE @ReturnValue    VARCHAR(1000)
	DECLARE @Length INT
	DECLARE @sourcevalue VARCHAR (255)
	/*______________________________________________
	**Initialization and remove Location Info from FilePath
	**______________________________________________*/

DECLARE @vcDay varchar (5)
	DECLARE @vcMonth varchar (5)
	DECLARE @vcYear varchar (6)

	DECLARE @Day INT
	DECLARE @Month INT
	DECLARE @Year INT

	DECLARE @Result INT = 0

	SET @StringValue = REPLACE (@StringValue, '-', '/')
	SET @StringValue = REPLACE (@StringValue, '.', '/')
	SET @StringValue = REPLACE (@StringValue, '\', '/')
	SET @StringValue = REPLACE (@StringValue, ',', '/')
	SET @StringValue = REPLACE (@StringValue, ' ', '/')

	/***************** Handle pattern specific stuff **********************/
	IF @Pattern = 'DD/MM/YYYY'
	BEGIN
		/* Check basic structure of value*/
		IF @StringValue NOT LIKE '%/%/%'
		BEGIN
			SET @Result = 0
			RETURN @Result
		END
		
		SET @vcDay = LEFT (@StringValue, PATINDEX ( '%/%', @StringValue)-1)
		SET @vcMonth = SUBSTRING (@StringValue, PATINDEX ( '%/%', @StringValue)+1, LEN (@StringValue) - (PATINDEX ( '%/%', REVERSE (@StringValue)) + PATINDEX ('%/%', @StringValue)))
		SET @vcYear = RIGHT (@StringValue, PATINDEX ( '%/%', REVERSE (@StringValue))-1)

		IF @vcYear NOT LIKE '[0-9][0-9][0-9][0-9]'
			BEGIN
				SET @Result = 0
				RETURN @Result
			END

		IF ISNUMERIC (@vcDay) = 1 AND ISNUMERIC (@vcMonth) = 1 AND ISNUMERIC (@vcYear) = 1
			BEGIN 
				SET @Day = @vcDay
				SET @Month = @vcMonth
				SET @Year = @vcYear
			END 
		ELSE
			BEGIN
				SET @Result = 0
				RETURN @Result
			END

	END

	
	IF @Pattern = 'DD/MM/YY'
	BEGIN
		/* Check basic structure of value*/
		IF @StringValue NOT LIKE '%/%/%'
		BEGIN
			SET @Result = 3
			RETURN @Result
		END
		
		SET @vcDay = LEFT (@StringValue, PATINDEX ( '%/%', @StringValue)-1)
		SET @vcMonth = SUBSTRING (@StringValue, PATINDEX ( '%/%', @StringValue)+1, LEN (@StringValue) - (PATINDEX ( '%/%', REVERSE (@StringValue)) + PATINDEX ('%/%', @StringValue)))
		SET @vcYear = RIGHT (@StringValue, PATINDEX ( '%/%', REVERSE (@StringValue))-1)

		IF @vcYear NOT LIKE '[0-9][0-9]' 
			BEGIN
				SET @Result = 0
				RETURN @Result
			END

		IF ISNUMERIC (@vcDay) = 1 AND ISNUMERIC (@vcMonth) = 1 AND ISNUMERIC (@vcYear) = 1
			BEGIN 
				SET @Day = @vcDay
				SET @Month = @vcMonth
				SET @Year = @vcYear
			END 
		ELSE
			BEGIN
				SET @Result = 0
				RETURN @Result
			END

	END


	IF @Pattern = 'MM/DD/YYYY'
	BEGIN
		/* Check basic structure of value*/
		IF @StringValue NOT LIKE '%/%/%'
		BEGIN
			SET @Result = 0
			RETURN @Result
		END
		
		SET @vcMonth = LEFT (@StringValue, PATINDEX ( '%/%', @StringValue)-1)
		SET @vcDay = SUBSTRING (@StringValue, PATINDEX ( '%/%', @StringValue)+1, LEN (@StringValue) - (PATINDEX ( '%/%', REVERSE (@StringValue)) + PATINDEX ('%/%', @StringValue)))
		SET @vcYear = RIGHT (@StringValue, PATINDEX ( '%/%', REVERSE (@StringValue))-1)

		IF @vcYear NOT LIKE '[0-9][0-9][0-9][0-9]'
			BEGIN
				SET @Result = 0
				RETURN @Result
			END

		IF ISNUMERIC (@vcDay) = 1 AND ISNUMERIC (@vcMonth) = 1 AND ISNUMERIC (@vcYear) = 1
			BEGIN 
				SET @Day = @vcDay
				SET @Month = @vcMonth
				SET @Year = @vcYear
			END 
		ELSE
			BEGIN
				SET @Result = 0
				RETURN @Result
			END
		--SELECT @Month = LEFT(@StringValue, 2)
		--SELECT @Day = SUBSTRING(@StringValue, 4,2)
		--SELECT @Year = SUBSTRING(@StringValue, 7,4)

	END

		IF @Pattern = 'MM/DD/YY'
	BEGIN
		/* Check basic structure of value*/
		IF @StringValue NOT LIKE '%/%/%'
		BEGIN
			SET @Result = 0
			RETURN @Result
		END
		
		SET @vcMonth = LEFT (@StringValue, PATINDEX ( '%/%', @StringValue)-1)
		SET @vcDay = SUBSTRING (@StringValue, PATINDEX ( '%/%', @StringValue)+1, LEN (@StringValue) - (PATINDEX ( '%/%', REVERSE (@StringValue)) + PATINDEX ('%/%', @StringValue)))
		SET @vcYear = RIGHT (@StringValue, PATINDEX ( '%/%', REVERSE (@StringValue))-1)

		IF @vcYear NOT LIKE '[0-9][0-9]'
			BEGIN
				SET @Result = 0
				RETURN @Result
			END

		IF ISNUMERIC (@vcDay) = 1 AND ISNUMERIC (@vcMonth) = 1 AND ISNUMERIC (@vcYear) = 1
			BEGIN 
				SET @Day = @vcDay
				SET @Month = @vcMonth
				SET @Year = @vcYear
			END 
		ELSE
			BEGIN
				SET @Result = 0
				RETURN @Result
			END
		--SELECT @Month = LEFT(@StringValue, 2)
		--SELECT @Day = SUBSTRING(@StringValue, 4,2)
		--SELECT @Year = SUBSTRING(@StringValue, 7,4)

	END



	IF @Pattern = 'YYYYMMDD'
	BEGIN
		/* Check basic structure of value*/
		IF @StringValue NOT LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
		BEGIN
			SET @Result = 0
			RETURN @Result
		END

		SELECT @Year = LEFT(@StringValue, 4)
		SELECT @Month = SUBSTRING(@StringValue, 5,2)
		SELECT @Day = SUBSTRING(@StringValue, 7,2)
	END

	IF @Year < 0 AND @Year > 9999
	BEGIN
		SET @Result = 5
		RETURN @Result
	END

	/***************** Handle date value checks **********************/
	IF  DQ.fnIsLeapYear (@Year) = 1
	BEGIN
		IF @Month in (2) 
		BEGIN
			IF @Day BETWEEN 1 AND 29
				BEGIN
					SET @Result = 1
					--PRINT @Result
				END
			ELSE
				BEGIN
					SET @Result = 0
--						PRINT @Result
					RETURN @Result
				END
		END
	END

	IF  DQ.fnIsLeapYear (@Year) = 0
	BEGIN
		IF @Month in (2) 
		BEGIN
			IF @Day BETWEEN 1 AND 28
				BEGIN
					SET @Result = 1
--						PRINT @Result
				END
			ELSE
				BEGIN
					SET @Result = 0
--						PRINT @Result
					RETURN @Result
				END
		END
	END

	IF @Month in (1,3,5,7,8,10,12) 
	BEGIN
		IF @Day BETWEEN 1 AND 31
			BEGIN
				SET @Result = 1
--					PRINT '12'
			END
		ELSE 
			BEGIN
				SET @Result = 0
--					PRINT '12X'
				RETURN @Result
			END
	END

	IF @Month in (4,6,9,11) 
	BEGIN
		IF @Day BETWEEN 1 AND 30
			BEGIN
				SET @Result = 1
--					PRINT '11'
			END
		ELSE 
			BEGIN
				SET @Result = 0
--					PRINT '11X'
				RETURN @Result
		END
	END 

	RETURN @Result
END


