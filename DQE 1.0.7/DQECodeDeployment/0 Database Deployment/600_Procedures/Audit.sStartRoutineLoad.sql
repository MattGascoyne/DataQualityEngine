USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sStartRoutineLoad'
				AND SPECIFIC_SCHEMA = 'Audit') 
BEGIN 
	DROP PROC [Audit].[sStartRoutineLoad]
END

GO

CREATE PROCEDURE [Audit].[sStartRoutineLoad]
	@ParentLoadId int = 0, 
	@ExecutionId uniqueidentifier, 
	@RoutineId uniqueidentifier,
	@VersionId uniqueidentifier = null,
	@PackageName NVarchar(250) = null,
	@RoutineType VARCHAR (50) = 'Package',
	@LoadProcess varchar(250) = NULL,
	@LoadId int Output
AS

/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 28/11/2014
**     Approx RunTime:
**     Desc: Inserts a record into the Audit.RoutineLoad table each time a package or routine is called.
				The package will spawn a unique identifier for the calling routine with a link to the 
				parent package or routine. 
				The record spawned is relatively simple and states the starttime of the routine/ package.
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					@ParentLoadId			- optional - the LoadId of the parent package.
--											- required if @LoadProcess is null
--					@ExecutionId			- the unique identifier for the package execution
--					@RoutineId				- the unique identifier for the package
--					@PackageName			- Optional: Name of the package or procedure
--					@RoutineType			- States the type of routine: typically package or stored procedure
											- Defaults to 'Package'
--					@LoadProcess			- optional - the short descriptio for the load process.
--											- required if @ParentLoadId = 0
**
**     Output
**     ----------
--					@LoadId					- Output for resultant LoadId for new load
** 
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**     MG     15/11/2015    Created
*******************************************************************************/

DECLARE @SystemId int, 
		@EnvironmentId int, 
		@LoadStatusName VARCHAR (20), 
		@IsLoadProcessPackage bit, 
		@LoadProcessId int,
		@StartTime DATETIME


--either @ParentLoadId or @LoadProcess must contain real values for the Load Process to be ascertained
IF @ParentLoadId = 0 AND @LoadProcess IS NULL
BEGIN
	RAISERROR ('Provide valid @ParentLoadId, @LoadProcess values when creating a new LoadId', 16, 1) WITH SETERROR;
	RETURN;
END

SET @LoadId = 0
SET @LoadProcessId = 0
SELECT @StartTime = GETDATE()


--catch bad @RoutineId values
IF @RoutineId IS NULL
BEGIN
	RAISERROR ('Invalid @RoutineId values value in call to Obtain New LoadId', 16, 1) WITH SETERROR;
	RETURN
END

SET @ParentLoadId = nullif(@ParentLoadId, 0)

-- Insert new load
INSERT INTO Audit.RoutineLoad
	( ParentLoadId, PackageGUID, ExecutionGUID,  PackageName, RoutineType, LoadStatusName, StartTime, LoadProcess, PackageVersionGUID )
VALUES 
	( @ParentLoadId, @RoutineId, @ExecutionId ,  @PackageName, @RoutineType, @LoadStatusName,  @StartTime,  @LoadProcess, @VersionId )
-- get the inserted Identity
set @LoadId = @@Identity

RETURN;


GO


