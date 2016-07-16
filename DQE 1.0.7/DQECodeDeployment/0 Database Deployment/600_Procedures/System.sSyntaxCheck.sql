USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sSyntaxCheck'
				AND SPECIFIC_SCHEMA = 'System') 
BEGIN 
	DROP PROC [System].[sSyntaxCheck]
END

GO

CREATE Procedure [System].[sSyntaxCheck] (@SearchValue AS varchar(256))

AS

/******************************************************************************
**     Author:       Dartec Systems (Sunil Shah)
**     Created Date: 15/11/2015
**     Desc: Used as a wrapper to keep a history of all code and rules generated
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
**
**     Output
**     ----------
--		Success: None
--		Failure: RaiseError			
** 
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**     MG     15/11/2015    Created
*******************************************************************************/

SELECT DISTINCT ObjectName = SCHEMA_NAME(P.Schema_ID) + '.' + P.Name--, Definition
FROM	[sys].[procedures] P
		INNER JOIN sys.sql_modules m ON p.object_id = m.object_id
WHERE	definition Like '%' + @SearchValue + '%'
ORDER BY 1

GO