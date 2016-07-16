USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sDropSYNONYM'
				AND SPECIFIC_SCHEMA = 'System') 
BEGIN 
	DROP PROC [System].[sDropSYNONYM]
END

GO

CREATE PROCEDURE [System].[sDropSYNONYM] (@SYNONYM nVarchar(256))

AS

/******************************************************************************
**	Author:			 Dartec Systems (Contributor: Sunil Shah)
**	Approx RunTime:
**	Desc:			Stored Proc to Drop a Synonym
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
**  SS  27/01/2016  Created 
*******************************************************************************/

DECLARE @SQL nvarchar(512)

IF Exists(	SELECT	* 
			FROM	sys.sysObjects SO
			WHERE	SO.Name = REPLACE(REPLACE(@SYNONYM, '[', ''), ']', '')
					AND [TYPE] = 'SN')
BEGIN
	SELECT @SQL = 'DROP SYNONYM ' + @SYNONYM
	EXEC (@SQL)
END