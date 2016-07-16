USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'DQAppActionType'
		 AND TABLE_SCHEMA = 'MDS' ) 

BEGIN 

	CREATE TABLE [MDS].[DQAppActionType](
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
		[Description] [nvarchar](255) NULL
	) ON [PRIMARY]

END

GO