USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'DQAppDataTypeConversion'
		 AND TABLE_SCHEMA = 'MDS' ) 

BEGIN 

CREATE TABLE [MDS].[DQAppDataTypeConversion](
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
	[SourceDataType_Code] [nvarchar](250) NULL,
	[SourceDataType_Name] [nvarchar](250) NULL,
	[SourceDataType_ID] [int] NULL,
	[DestinationDataType_Code] [nvarchar](250) NULL,
	[DestinationDataType_Name] [nvarchar](250) NULL,
	[DestinationDataType_ID] [int] NULL,
	[ConversionType_Code] [nvarchar](250) NULL,
	[ConversionType_Name] [nvarchar](250) NULL,
	[ConversionType_ID] [int] NULL,
	[ConversionActionType_Code] [nvarchar](250) NULL,
	[ConversionActionType_Name] [nvarchar](250) NULL,
	[ConversionActionType_ID] [int] NULL
) ON [PRIMARY]

END

go