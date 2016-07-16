USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sDropView'
				AND SPECIFIC_SCHEMA = 'System') 
BEGIN 
	DROP PROC [System].[sDropView]
END

GO

CREATE PROCEDURE [System].[sDropView] (@View nVarchar(256))

AS

/******************************************************************************
**	Author:			 Dartec Systems (Contributor: Sunil Shah)
**	Created Date:	12/10/2015
**	Approx RunTime:
**	Desc:			Stored Proc to Drop a View
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

DECLARE @SQL varchar(256)

IF Object_ID(@View, N'V') IS NOT NULL
BEGIN
	SELECT @SQL = 'DROP View ' + @View
	EXEC (@SQL)
END

RETURN(0)