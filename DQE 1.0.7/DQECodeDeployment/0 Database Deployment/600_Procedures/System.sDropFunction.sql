USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sDropFunction'
				AND SPECIFIC_SCHEMA = 'System') 
BEGIN 
	DROP PROC [System].[sDropFunction]
END

GO

CREATE Procedure [System].[sDropFunction] (@Function as varchar(128))

/******************************************************************************
**	Author:			 Dartec Systems (Contributor: Sunil Shah)
**	Created Date:	12/10/2015
**	Approx RunTime:
**	Desc:			Proc to drop procedures
**
**	Return values:  None
** 
**	Called by: 
**              
**	Parameters: 
**	Input
**	---------- 
**	@Function - Function name e.g. 'Audit.fTest'
**
**	Output
**	----------
**	  
*******************************************************************************
**	Change History
*******************************************************************************
**	By:	Date:		Description:
**	---	--------	-----------------------------------------------------------
**  SS  27/11/2015  Created
*******************************************************************************/

AS

DECLARE @SQL varchar(256)

IF Object_ID(@Function, N'FN') IS NOT NULL
BEGIN
	SELECT @SQL = 'DROP FUNCTION ' + @Function
	
	EXEC (@SQL)
END
