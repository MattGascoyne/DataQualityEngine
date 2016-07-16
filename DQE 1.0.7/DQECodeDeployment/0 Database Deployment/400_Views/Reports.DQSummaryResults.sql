USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'DQSummaryResults'
		 AND TABLE_SCHEMA = 'Reports' ) 
BEGIN 
	DROP VIEW [Reports].[DQSummaryResults]
END

GO

CREATE VIEW [Reports].[DQSummaryResults]

as

SELECT  DQH.LoadId
		, LHM.LoadProcess
		, LH.ParentLoadId
		, LH.MasterLoadId
		, LH.IsMasterLoadPackage
		, AE.RuleDomain_Code as RuleDomainCode
		, AE.RuleDomain_Name as RuleDomainName
		, DQH.RuleType
		, DQH.RuleId as RuleCode 
		, DQH.CheckName AS RuleName 
		, DQH.RuleEntityAssociationId as RuleEntityAssociationCode
		, DQH.RuleEntityAssociationName
		, AE.Code as EntityCode
		, AE.SourceEntity
		, AE.SourceSchema
		, AE.SourceDatabase
		, AE.[Database] AS DQDatabase
		, AE.[Schema] AS DQSchema
		, AE.EntityName AS DQEntity
		, DQH.ColumnName AS EvaluationColumn
		, DQH.DQMessage
		, DQH.RowsAffected
		, DQH.PercentageValue
		, LH.DurationInSeconds
		, DQH.SeverityId
		, DQH.SeverityName
		, LH.StartTime
		, LH.EndTime
		, LH.ErrorDescription
		, LH.ErroredRoutine
		, LHM.StartTime as MasterStartTime
		, LHM.EndTime as MasterEndTime
		, REA.IsActive_Name AS IsActiveName
FROM [DQ].[DataQualityHistory] DQH
	INNER JOIN [MDS].[DQRuleEntityAssociation] REA
		ON DQH.RuleEntityAssociationId = REA.Code
	INNER JOIN 	[MDS].[DQAppEntity] AE
		ON REA.DQEntity_Code = AE.Code
	INNER JOIN [Audit].[RoutineLoadHistory] LH
		ON DQH.LoadId = LH.LoadId
	INNER JOIN [Audit].[RoutineLoadHistory] LHP
		ON LH.ParentLoadId = LHP.LoadId
	INNER JOIN [Audit].[RoutineLoadHistory] LHM
		ON LH.MasterLoadId = LHM.LoadId



GO