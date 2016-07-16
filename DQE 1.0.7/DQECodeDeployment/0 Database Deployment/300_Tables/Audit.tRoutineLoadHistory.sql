USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'RoutineLoadHistory'
		 AND TABLE_SCHEMA = 'Audit' ) 

BEGIN

CREATE TABLE [Audit].[RoutineLoadHistory](
	[IsMasterLoadPackage] [int] NOT NULL,
	[MasterLoadId] [varchar](20) NULL,
	[ParentLoadId] [int] NULL,
	[LoadId] [int] NULL,
	[PackageName] [varchar](250) NULL,
	[RoutineType] [varchar](50) NULL,
	[LoadProcess] [varchar](255) NULL,
	[DatabaseName] [varchar](255) NULL,
	[SchemaName] [varchar](255) NULL,
	[EntityName] [varchar](255) NULL,
	[RuleType] [varchar](50) NULL,
	[RuleId] [int] NULL,
	[LoadStatusName] [varchar](20) NULL,
	[RoutineErrorID] [int] NULL,
	[ErrorDescription] [varchar](1000) NULL,
	[ErroredRoutine] [varchar](255) NULL,
	[DurationInSeconds] [int] NULL,
	[StartTime] [datetime] NULL,
	[EndTime] [datetime] NULL
) ON [PRIMARY]

END

GO


