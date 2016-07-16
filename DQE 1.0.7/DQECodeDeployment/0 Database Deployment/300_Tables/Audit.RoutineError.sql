USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'RoutineError'
		 AND TABLE_SCHEMA = 'Audit' ) 

BEGIN 

	CREATE TABLE [Audit].[RoutineError](
		[RoutineErrorID] [int] IDENTITY(1,1) NOT NULL,
		[LoadId] [int] NULL,
		[ErrorCode] [int] NULL,
		[ErrorDescription] [ntext] NULL,
		[ErrorDateTime] [datetime] NULL,
		[SourceName] [nvarchar](255) NULL,
	 CONSTRAINT [PK_PackageExecutionError] PRIMARY KEY CLUSTERED 
	(
		[RoutineErrorID] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
	) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

END
GO