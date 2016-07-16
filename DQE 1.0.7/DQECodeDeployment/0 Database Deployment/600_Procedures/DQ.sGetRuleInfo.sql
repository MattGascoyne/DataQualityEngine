USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sGetRuleInfo'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sGetRuleInfo]
END

GO


CREATE PROCEDURE [DQ].[sGetRuleInfo] @RuleAssociationCode INT

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Utility procedure to return important information about an individual rule
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					@RuleEntityAssociationCode		- The rule identifier used to return all of information used to create, log and execute the rule
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
**     MG     01/03/2016    Release 1.0.3
*******************************************************************************/


AS

SELECT 
REA.IsActive_Name AS RuleAssociationIsActive,
REA.Code AS RuleAssociationCode,
REA.Name AS RuleAssociationName,
DAE.Code AS DQEntityCode , 
DAE.RuleDomain_Code AS DQDomainCode , 
DAE.RuleDomain_Name AS DQDomainName , 
DAE.[Database] +'.' + DAE.[Schema] + '.' + DAE.EntityName AS DQEntity,
DAE.SourceDatabase +'.' + DAE.SourceSchema + '.' + DAE.SourceEntity AS DQSourceEntity,
REA.RuleType_Name AS RuleType, 
COALESCE (ExpressionRule_Code, HarmonizationRule_Code, ProfilingRule_Code, ReferenceRule_Code, ValueCorrectionRule_Code) AS RuleCode,
COALESCE (ExpressionRule_Name, HarmonizationRule_Name, ProfilingRule_Name, ReferenceRule_Name, ValueCorrectionRule_Name) AS RuleCode,
ExecutionSequence_Name AS ExecutionSequence,
EvaluationColumn,
OutputColumn,
StatusColumn,
OptionalFilterClause
FROM [MDS].[DQRuleEntityAssociation] REA
	INNER JOIN MDS.DQAppEntity DAE
		ON REA.DQEntity_Code = DAE.Code
WHERE REA.Code = @RuleAssociationCode


GO


