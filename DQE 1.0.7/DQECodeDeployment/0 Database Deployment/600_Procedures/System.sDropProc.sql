USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sDropProc'
				AND SPECIFIC_SCHEMA = 'System') 
BEGIN 
	DROP PROC [System].[sDropProc]
END

GO

CREATE Procedure [System].[sDropProc] (@Proc as varchar(128))

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
**	@Proc - Procedure name e.g. 'Audit.sTest'
**
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

DECLARE @SQL varchar(256)

IF Object_ID(@Proc, N'P') IS NOT NULL
	AND Object_ID(@Proc, N'P')  != @@PROCID
BEGIN
	SELECT @SQL = 'DROP PROCEDURE ' + @Proc
	
	EXEC (@SQL)
END
