USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sEndRoutineLoad'
				AND SPECIFIC_SCHEMA = 'Audit') 
BEGIN 
	DROP PROC [Audit].[sEndRoutineLoad]
END

GO


/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Approx RunTime:
**     Desc: Used to close an active Load record.
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					@LoadId					- the record you want to end 
--					@LoadStatusShortName	- Indicate how you want to record the record as completing (Success/ Failure)
--					@TotalRows				- record the number of row affected by the operation
--					@BadRows				- record the number of bad rows affected by the operation
**
**     Output
**     ----------
--					
** 
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**     MG     01/03/2016    Release 1.0.3
*******************************************************************************/
CREATE PROCEDURE [Audit].[sEndRoutineLoad]
	@LoadId int, @LoadStatusShortName varchar(10),  @TotalRows int = 0, @BadRows int = 0
AS


DECLARE @EndTime datetime

SELECT @EndTime = GETDATE ()
--catch bad @LoadStatusShortName values
IF @LoadStatusShortName NOT IN ('SUCCESS', 'FAILURE', 'LOGGED', 'NOT LOGGED')
	Begin
		RaisError ('Invalid @LoadStatusShortName value in call to Update Package Load', 16, 1) WITH SETERROR
		Return;
	End
ELSE
	UPDATE Audit.RoutineLoad 
		SET LoadStatusName = @LoadStatusShortName,
		EndTime = @EndTime,
		Duration = DateDiff(Second, StartTime, @EndTime)
	WHERE LoadId = @LoadId

Return;




GO

