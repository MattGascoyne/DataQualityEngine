USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'DataQualityHistory'
		 AND TABLE_SCHEMA = 'DQ' ) 

BEGIN 

	CREATE TABLE [DQ].[DataQualityHistory](
		[DQLogId] [int] IDENTITY(1,1) NOT NULL,
		[EntityId] [int] NULL,
		[LoadId] [int] NULL,
		[SeverityId] [int] NULL,
		[SeverityName] [varchar](255) NULL,
		[EntityName] [varchar](255) NULL,
		[ColumnName] [varchar](255) NULL,
		[RuleType] [varchar](255) NULL,
		[CheckName] [varchar](255) NULL,
		[DQMessage] [varchar](255) NULL,
		[RuleId] [int] NULL,
		[RuleEntityAssociationId] [int] NULL,
		[RuleEntityAssociationName] [varchar](255) NULL,
		[RowsAffected] [varchar](255) NULL,
		[PercentageValue] [float] NULL,
		[DateCreated] [int] NULL,
		[TimeCreated] [time](7) NULL
	) ON [PRIMARY]

END 
GO