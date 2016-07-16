USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sAddColumn'
				AND SPECIFIC_SCHEMA = 'System') 
BEGIN 
	DROP PROC [System].[sAddColumn]
END

GO


CREATE Procedure [System].[sAddColumn] (
	@TableName varchar(256)
	, @ColumnName varchar(256)
	, @DataType varchar(32))


/******************************************************************************
**	Author:			 Dartec Systems (Contributor: Sunil Shah)
**	Created Date:	12/10/2015
**	Approx RunTime:
**	Desc:			Stored Proc to Add a column to a table
**
**	Return values:  None
** 
**	Called by: 
**              
**	Parameters: 
**	Input
**	---------- 
**	Output
**	----------
**	  
*******************************************************************************
**	Change History
*******************************************************************************
**	By:	Date:		Description:
**	---	--------	-----------------------------------------------------------
**  SS  12/10/2015  Created 
*******************************************************************************/

AS

DECLARE @SQL varchar(2048) = ''

SELECT @SQL = 'ALTER Table ' + @TableName + ' ADD ' + @ColumnName + ' ' + @DataType

BEGIN TRY

	EXEC (@SQL)

END TRY

BEGIN CATCH
END Catch

RETURN(0)