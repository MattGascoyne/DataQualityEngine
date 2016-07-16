USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'DataQualityPrimaryKeyValues'
		 AND TABLE_SCHEMA = 'DQ' ) 

BEGIN 

	CREATE TABLE [DQ].[DataQualityPrimaryKeyValues](
		[PKLogId] [int] IDENTITY(1,1) NOT NULL,
		[EntityId] [int] NULL,
		[RowId] [varchar](255) NULL,
		[PrimaryKeyColumn] [varchar](255) NULL,
		[PrimaryKeyValue] [varchar](255) NULL,
		[LoadId] [int] NULL,
		[DateCreated] [int] NULL,
		[TimeCreated] [time](7) NULL
	) ON [PRIMARY]

END

GO