USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'DQAppEntity'
		 AND TABLE_SCHEMA = 'MDS' ) 

BEGIN 

	CREATE TABLE [MDS].[DQAppEntity](
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
		[RuleDomain_Code] [nvarchar](250) NULL,
		[RuleDomain_Name] [nvarchar](250) NULL,
		[RuleDomain_ID] [int] NULL,
		[PrimaryKey] [nvarchar](255) NULL,
		[Database] [nvarchar](255) NULL,
		[Schema] [nvarchar](255) NULL,
		[EntityName] [nvarchar](255) NULL,
		[SourceDatabase] [nvarchar](255) NULL,
		[SourceSchema] [nvarchar](255) NULL,
		[SourceEntity] [nvarchar](255) NULL,
		[IsActive_Code] [nvarchar](250) NULL,
		[IsActive_Name] [nvarchar](250) NULL,
		[IsActive_ID] [int] NULL
	) ON [PRIMARY]

END

GO