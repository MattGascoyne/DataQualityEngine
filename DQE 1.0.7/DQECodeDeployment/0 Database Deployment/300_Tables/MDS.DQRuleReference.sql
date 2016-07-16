USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'DQRuleReference'
		 AND TABLE_SCHEMA = 'MDS' ) 

BEGIN 


CREATE TABLE [MDS].[DQRuleReference](
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
	[IsActive_Code] [nvarchar](250) NULL,
	[IsActive_Name] [nvarchar](250) NULL,
	[IsActive_ID] [int] NULL,
	[Severity_Code] [nvarchar](250) NULL,
	[Severity_Name] [nvarchar](250) NULL,
	[Severity_ID] [int] NULL,
	[Ruleset_Code] [nvarchar](250) NULL,
	[Ruleset_Name] [nvarchar](250) NULL,
	[Ruleset_ID] [int] NULL,
	[ReferenceDatabase] [nvarchar](255) NULL,
	[ReferenceSchema] [nvarchar](255) NULL,
	[ReferenceEntity] [nvarchar](255) NULL,
	[ReferenceColumn] [nvarchar](255) NULL,
	[ReferenceType_Code] [nvarchar](250) NULL,
	[ReferenceType_Name] [nvarchar](250) NULL,
	[ReferenceType_ID] [int] NULL,
	[ReferenceList_Code] [nvarchar](250) NULL,
	[ReferenceList_Name] [nvarchar](250) NULL,
	[ReferenceList_ID] [int] NULL,
	[JoinLogic] [nvarchar](4000) NULL,
	[AttributeComparisons] [nvarchar](4000) NULL
) ON [PRIMARY]

END
GO

--IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'DQRuleReference'
--				AND TABLE_SCHEMA = 'DQ'
--				AND COLUMN_NAME = 'JoinLogic')
--		BEGIN
--		ALTER TABLE [MDS].[DQRuleReference]
--		ADD JoinLogic [nvarchar] (4000)
--		END
--GO

--IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'DQRuleReference'
--				AND TABLE_SCHEMA = 'DQ'
--				AND COLUMN_NAME = 'AttributeComparisons')
--		BEGIN
--		ALTER TABLE [MDS].[DQRuleReference]
--		ADD AttributeComparisons [nvarchar] (4000)
--		END
--GO