USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sGetDomainEntityExecutionSequenceCount'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sGetDomainEntityExecutionSequenceCount]
END

GO

create PROC [DQ].[sGetDomainEntityExecutionSequenceCount]
@DQEntityName VARCHAR (255)
, @DomainName VARCHAR (255)
, @ExecutionSequence INT
AS

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Gets the count of rules within the specified execution sequence
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

SELECT COUNT (*) as ExecutionSequenceCount
FROM MDS.[DQRuleEntityAssociation] REA
	INNER JOIN MDS.[DQAppEntity] AE
		ON REA.[DQEntity_Code] = AE.Code
WHERE AE.Name = @DQEntityName
	AND AE.RuleDomain_Name = @DomainName
	AND ISNULL (REA.ExecutionSequence_Code, 1) = @ExecutionSequence




GO
