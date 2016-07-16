USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sTableSearch'
				AND SPECIFIC_SCHEMA = 'System') 
BEGIN 
	DROP PROC [System].[sTableSearch]
END

GO

CREATE Procedure [System].[sTableSearch] (@SearchValue AS varchar(256))

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

AS

SELECT DISTINCT SCHEMA_NAME(Schema_ID) + '.' + OBJECT_NAME(SO.Object_ID)
From	sys.objects SO
Where	SO.Type = 'U'
		AND SCHEMA_NAME(Schema_ID) + '.' + OBJECT_NAME(SO.Object_ID) Like '%' + @SearchValue + '%'

GO