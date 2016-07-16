USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'DQRuleEntityAssociation'
		 AND TABLE_SCHEMA = 'MDS' ) 

BEGIN 

CREATE TABLE [MDS].[DQRuleEntityAssociation](
	[ID] [int] NULL,
	[MUID] [uniqueidentifier] NULL,
	[VersionName] [nvarchar](50) NULL,
	[VersionNumber] [int] NULL,
	[VersionFlag] [nvarchar](50) NULL,
	[Name] [nvarchar](250) NULL,
	[Code] [nvarchar](250) NULL,
	[ChangeTrackingMask] [int] NULL,
	[EnterDateTime] [datetime2](3) NULL,
	[EnterUserName] [nvarchar](100) NULL,
	[EnterVersionNumber] [int] NULL,
	[LastChgDateTime] [datetime2](3) NULL,
	[LastChgUserName] [nvarchar](100) NULL,
	[LastChgVersionNumber] [int] NULL,
	[ValidationStatus] [nvarchar](250) NULL,
	[DQEntity_Code] [nvarchar](250) NULL,
	[DQEntity_Name] [nvarchar](250) NULL,
	[DQEntity_ID] [int] NULL,
	[ExecutionSequence_Code] [nvarchar](250) NULL,
	[ExecutionSequence_Name] [nvarchar](250) NULL,
	[ExecutionSequence_ID] [int] NULL,
	[EvaluationColumn] [nvarchar](255) NULL,
	[Ruleset_Code] [nvarchar](250) NULL,
	[Ruleset_Name] [nvarchar](250) NULL,
	[Ruleset_ID] [int] NULL,
	[ExpressionRule_Code] [nvarchar](250) NULL,
	[ExpressionRule_Name] [nvarchar](250) NULL,
	[ExpressionRule_ID] [int] NULL,
	[HarmonizationRule_Code] [nvarchar](250) NULL,
	[HarmonizationRule_Name] [nvarchar](250) NULL,
	[HarmonizationRule_ID] [int] NULL,
	[ProfilingRule_Code] [nvarchar](250) NULL,
	[ProfilingRule_Name] [nvarchar](250) NULL,
	[ProfilingRule_ID] [int] NULL,
	[ReferenceRule_Code] [nvarchar](250) NULL,
	[ReferenceRule_Name] [nvarchar](250) NULL,
	[ReferenceRule_ID] [int] NULL,
	[ValueCorrectionRule_Code] [nvarchar](250) NULL,
	[ValueCorrectionRule_Name] [nvarchar](250) NULL,
	[ValueCorrectionRule_ID] [int] NULL,
	[OutputColumn] [nvarchar](255) NULL,
	[StatusColumn] [nvarchar](255) NULL,
	[DateFrom] [datetime2](3) NULL,
	[DateTo] [datetime2](3) NULL,
	[IsActive_Code] [nvarchar](250) NULL,
	[IsActive_Name] [nvarchar](250) NULL,
	[IsActive_ID] [int] NULL,
	[RuleType_Code] [nvarchar](250) NULL,
	[RuleType_Name] [nvarchar](250) NULL,
	[RuleType_Id] [int] NULL,
	[OptionalFilterClause] [nvarchar](255) NULL,
	[TransformationRule_Code] [nvarchar](250) NULL,
	[TransformationRule_Name] [nvarchar](250) NULL,
	[TransformationRule_ID] [int] NULL
) ON [PRIMARY]


END

GO