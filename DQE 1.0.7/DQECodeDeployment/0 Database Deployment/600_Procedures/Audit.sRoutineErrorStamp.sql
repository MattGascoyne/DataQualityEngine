USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sRoutineErrorStamp'
				AND SPECIFIC_SCHEMA = 'Audit') 
BEGIN 
	DROP PROC [Audit].[sRoutineErrorStamp]
END

GO

CREATE PROCEDURE [Audit].[sRoutineErrorStamp]
	@LoadId int,
	@ErrorCode int,
	@ErrorDescription ntext,
	@SourceName nvarchar(255)
AS


/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Inserts errors into the error log.
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					@LoadId				- The LoadId in which the error occurred
--					@ErrorCode			- A meaningful code to represent the error
--					@ErrorDescription	- A meaningful description of the error 
--					@SourceName			- A meaningful name to indicate where the error occurred
**
**     Output
**     ----------
--		Success: None
--		Failure: RaiseError			
** 
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**     MG     15/11/2015    Created
*******************************************************************************/
BEGIN

	/* Ensure the Load record has a FAILURE flag*/
	UPDATE audit.RoutineLoad
	SET
		EndTime = getdate()
		, [LoadStatusName] = 'FAILURE'
	WHERE LoadID = @LoadId

	/* Insert an error message into the error log*/
	INSERT INTO audit.RoutineError
	(
		LoadId,
		ErrorCode,
		ErrorDescription,
		ErrorDateTime,
		SourceName	
	)
	VALUES
	(
		@LoadId,
		@ErrorCode,
		@ErrorDescription,
		getdate(),
		@SourceName
	)
END	


GO
