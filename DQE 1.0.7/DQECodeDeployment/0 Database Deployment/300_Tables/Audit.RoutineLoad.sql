USE [DataQualityDB]
GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'RoutineLoad'
		 AND TABLE_SCHEMA = 'Audit' ) 

BEGIN

	CREATE TABLE [Audit].[RoutineLoad](
		[LoadId] [int] IDENTITY(1,1) NOT NULL,
		[ParentLoadId] [int] NULL,
		[ExecutionId] [int] NULL,
		[ExecutionGUID] [uniqueidentifier] NULL,
		[PackageVersionGUID] [uniqueidentifier] NULL,
		[PackageGUID] [uniqueidentifier] NULL,
		[PackageName] [varchar](250) NULL,
		[RoutineType] [varchar](50) NULL,
		[LoadProcess] [varchar](255) NULL,
		[LoadStatusName] [varchar](20) NULL,
		[StartTime] [datetime] NULL,
		[EndTime] [datetime] NULL,
		[Duration] [bigint] NULL,
		[CreatedUser] [sysname] NOT NULL CONSTRAINT [DF__tPackageL__Creat__267ABA7A]  DEFAULT (suser_sname()),
		[CreatedDate] [datetime] NOT NULL CONSTRAINT [DF__tPackageL__Creat__276EDEB3]  DEFAULT (getdate()),
		[UpdatedUser] [sysname] NOT NULL CONSTRAINT [DF__tPackageL__Updat__286302EC]  DEFAULT (suser_sname()),
		[UpdatedDate] [datetime] NOT NULL CONSTRAINT [DF__tPackageL__Updat__29572725]  DEFAULT (getdate()),
	 CONSTRAINT [PK_PackageLoad] PRIMARY KEY CLUSTERED 
	(
		[LoadId] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
	) ON [PRIMARY]
END

GO