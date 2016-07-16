USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'RuleExecutionHistory'
		 AND TABLE_SCHEMA = 'DQ' ) 

BEGIN 

	CREATE TABLE [DQ].[RuleExecutionHistory](
		[RXLogId] [int] IDENTITY(1,1) NOT NULL,
		[LoadId] [int] NULL,
		[DatabaseName] [varchar](255) NULL,
		[SchemaName] [varchar](255) NULL,
		[EntityName] [varchar](255) NULL,
		[RuleId] [int] NULL,
		[RuleSQLDescription] [varchar](255) NULL,
		[RuleType] [varchar](50) NULL,
		[RuleSQL] [varchar](max) NULL,
		[DateCreated] [int] NULL,
		[TimeCreated] [time](7) NULL
	) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

END

GO