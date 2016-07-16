USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'DQRuleHarmonization'
		 AND TABLE_SCHEMA = 'MDS' ) 

BEGIN 

CREATE TABLE [MDS].[DQRuleHarmonization](
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
	[Ruleset_Code] [nvarchar](250) NULL,
	[Ruleset_Name] [nvarchar](250) NULL,
	[Ruleset_ID] [int] NULL,
	[IsActive_Code] [nvarchar](250) NULL,
	[IsActive_Name] [nvarchar](250) NULL,
	[IsActive_ID] [int] NULL,
	[HarmonizationType_Code] [nvarchar](250) NULL,
	[HarmonizationType_Name] [nvarchar](250) NULL,
	[HarmonizationType_ID] [int] NULL,
	[SpecifiedCharacter] [nvarchar](255) NULL,
	[DateFormat_Code] [nvarchar](250) NULL,
	[DateFormat_Name] [nvarchar](250) NULL,
	[DateFormat_Id] [int] NULL,
	[ReplacingValue] [nvarchar](255) NULL,
	[BespokeFunction] [nvarchar](255) NULL
) ON [PRIMARY]

END

GO