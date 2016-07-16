USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sGetExecutionSequences'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sGetExecutionSequences]
END

GO

CREATE PROC [DQ].[sGetExecutionSequences]
AS

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Gets a list of available Execution Sequence Numbers (ASC 1 --> n)
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
** 
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**     MG     01/03/2016    Release 1.0.3
*******************************************************************************/

SELECT CAST (SequenceNumber AS INT) AS ExecutionSequence 
FROM MDS.DQExecutionSequence
ORDER BY CAST (SequenceNumber AS INT) ASC



GO


