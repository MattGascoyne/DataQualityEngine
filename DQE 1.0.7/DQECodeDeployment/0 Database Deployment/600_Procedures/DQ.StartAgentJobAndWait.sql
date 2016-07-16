USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'StartAgentJobAndWait'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[StartAgentJobAndWait]
END

GO

CREATE procedure [DQ].[StartAgentJobAndWait]
@job nvarchar(128), 
@maxwaitmins int = 2400,
@ParentLoadId INT = null,
@OutSuccessFlag  int OUTPUT

/******************************************************************************
**     Author:      TVdP (http://blog.boxedbits.com/archives/124)
**     Created Date: 06/07/2009
**     Desc: Starts a SQLAgent Job and waits for it to finish or until a specified wait period elapsed
**
**     Return values:@OutSuccessFlag	1 -> OK
**										0 -> still running after maxwaitmins
**
**     Called by:[DQ].[sExecuteJobDataQualityEngine]
**             
**     Parameters:
**     Input
**     ----------
--					@job: Name of job to run.
**
**     Output
**     ----------
					@OutSuccessFlag	1 -> OK
**									0 -> still running after maxwaitmins	
** 
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**	   TVdP	  06/07/2009	Created 	
**     MG     15/11/2015    Incorporated in DQE & modified
*******************************************************************************/

as begin

set NOCOUNT ON;
set XACT_ABORT ON;

	BEGIN TRY
	DECLARE	
		@running as int
		, @seccount as int
		, @maxseccount as int
		, @start_job as bigint
		, @run_status as int

		, @LoadId INT
		, @ExecutionId UNIQUEIDENTIFIER = newid()
		, @RoutineId UNIQUEIDENTIFIER = newId()
		, @PackageName NVARCHAR (250) = OBJECT_NAME(@@PROCID)
		, @LoadProcess VARCHAR (255) = NULL
		, @DQMessage VARCHAR (1000)
				
		, @Error VARCHAR(MAX)
		, @ErrorNumber INT
		, @ErrorSeverity VARCHAR (255)
		, @ErrorState VARCHAR (255)
		, @ErrorMessage VARCHAR(MAX)
		--, @ParentLoadId int = -1

	/* Start Audit*/
	SET @LoadProcess = 'Scheduled Job: Execute And Wait' 
	EXEC [Audit].[sStartRoutineLoad] @ParentLoadId = @ParentLoadId, @ExecutionId= @ExecutionId, @RoutineId = @RoutineId, @PackageName = @PackageName
			, @RoutineType = 'Stored Procedure' , @LoadProcess = @LoadProcess, @LoadId = @LoadId OUTPUT

	set @start_job = cast(convert(varchar, getdate(), 112) as bigint) * 1000000 + datepart(hour, getdate()) * 10000 + datepart(minute, getdate()) * 100 + datepart(second, getdate())

	set @maxseccount = 60*@maxwaitmins
	set @seccount = 0
	set @running = 0

	declare @job_owner sysname
	declare @job_id UNIQUEIDENTIFIER

	set @job_owner = SUSER_SNAME()

	-- get job id
	select @job_id=job_id
	from msdb.dbo.sysjobs sj
	where sj.name=@job

	-- invalid job name then exit with an error
	if @job_id is null
		RAISERROR (N'Unknown job: %s.', 16, 1, @job)

	-- output from stored procedure xp_sqlagent_enum_jobs is captured in the following table
	declare @xp_results TABLE ( job_id                UNIQUEIDENTIFIER NOT NULL,
								last_run_date         INT              NOT NULL,
								last_run_time         INT              NOT NULL,
								next_run_date         INT              NOT NULL,
								next_run_time         INT              NOT NULL,
								next_run_schedule_id  INT              NOT NULL,
								requested_to_run      INT              NOT NULL, -- BOOL
								request_source        INT              NOT NULL,
								request_source_id     sysname          COLLATE database_default NULL,
								running               INT              NOT NULL, -- BOOL
								current_step          INT              NOT NULL,
								current_retry_attempt INT              NOT NULL,
								job_state             INT              NOT NULL)

	-- start the job
	declare @r as int
	exec @r = msdb..sp_start_job @job

	-- quit if unable to start
	if @r<>0
		RAISERROR (N'Could not start job: %s.', 16, 2, @job)

	-- start with an initial delay to allow the job to appear in the job list (maybe I am missing something ?)
	WAITFOR DELAY '0:0:01';
	set @seccount = 1

	-- check job run state
	insert into @xp_results
	execute master.dbo.xp_sqlagent_enum_jobs 1, @job_owner, @job_id

	set @running= (SELECT top 1 running from @xp_results)

	while @running<>0 and @seccount < @maxseccount
	begin
		WAITFOR DELAY '0:0:01';
		set @seccount = @seccount + 1

		delete from @xp_results

		insert into @xp_results
		execute master.dbo.xp_sqlagent_enum_jobs 1, @job_owner, @job_id
		
		set @running= (SELECT top 1 running from @xp_results)
	end

	-- result: not ok (=1) if still running

	if @running <> 0 begin
		-- still running
		SET @OutSuccessFlag = 0
		--return 0
		
	end
	else begin

		-- did it finish ok ?
		set @run_status = 0

		select @run_status=run_status
		from msdb.dbo.sysjobhistory
		where job_id=@job_id
		  and cast(run_date as bigint) * 1000000 + run_time >= @start_job

		if @run_status=1
			BEGIN
				--return 1  --finished ok
				SET @OutSuccessFlag = 1
				--RETURN @OutValue
			END 
		else  --error
			BEGIN
				RAISERROR (N'job %s did not finish successfully.', 16, 2, @job)
				SET @OutSuccessFlag = 0
				--RETURN @OutValue
			END
	end

	/* End Audit as Success*/
	EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'SUCCESS'

	END TRY
	BEGIN CATCH
		SET @ErrorSeverity = '10' --CONVERT(VARCHAR(255), ERROR_SEVERITY())
		SET @ErrorState = CONVERT(VARCHAR(255), ERROR_STATE())
		SET @ErrorNumber = CONVERT(VARCHAR(255), ERROR_NUMBER())

		PRINT Error_Message()


		SET @Error =
			'(Proc: ' + OBJECT_NAME(@@PROCID)
			+ ' Line: ' + CONVERT(VARCHAR(255), ERROR_LINE())
			+ ' Number: ' + CONVERT(VARCHAR(255), ERROR_NUMBER())
			+ ' Severity: ' + CONVERT(VARCHAR(255), ERROR_SEVERITY())
			+ ' State: ' + CONVERT(VARCHAR(255), ERROR_STATE())
			+ ') '
			+ CONVERT(VARCHAR(255), ERROR_MESSAGE())

		/* Create a tidy error message*/
		SET @Error = @Error 

		/* Stamp the routine load value as failure*/
		EXEC [Audit].[sEndRoutineLoad] @LoadId = @LoadId, @LoadStatusShortName = 'FAILURE'
		/* Record the nature of the failure*/
		EXEC [Audit].[sRoutineErrorStamp] @LoadId = @LoadId, @ErrorCode = @ErrorNumber, @ErrorDescription = @Error, @SourceName=  @PackageName 
		SET @OutSuccessFlag = 0

		/*Raise an error*/
		RAISERROR (@Error, @ErrorSeverity, @ErrorState) WITH NOWAIT

	END CATCH

end
GO

