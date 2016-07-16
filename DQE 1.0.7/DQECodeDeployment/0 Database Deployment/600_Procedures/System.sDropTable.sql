USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sDropTable'
				AND SPECIFIC_SCHEMA = 'System') 
BEGIN 
	DROP PROC [System].[sDropTable]
END

GO

CREATE PROCEDURE [System].[sDropTable] (@TableName nVarchar(256))

AS

/******************************************************************************
**	Author:			 Dartec Systems (Contributor: Sunil Shah)
**	Created Date:	12/10/2015
**	Approx RunTime:
**	Desc:			Stored Proc to Drop a table
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

DECLARE @SQL nvarchar(512)
DECLARE @PartName_1 nVarchar(256)
DECLARE @PartName_2 nVarchar(256)

SELECT @PartName_1 = PARSENAME (@TableName, 1)
SELECT @PartName_2 = PARSENAME (@TableName, 2)

IF Exists(	SELECT	* 
			FROM	sys.Tables SO
					JOIN sys.Schemas SC ON SO.Schema_ID = SC.Schema_ID
			WHERE	SO.Name = @PartName_1
					AND SC.Name = ISNULL(@PartName_2, 'dbo'))

BEGIN
	SELECT @SQL = 'DROP Table ' + @TableName
	EXEC (@SQL)
END

RETURN(0)
