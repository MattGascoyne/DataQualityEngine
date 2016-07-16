USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'RoutineLoadHistory_10'
		 AND TABLE_SCHEMA = 'Audit' ) 
BEGIN 
	DROP VIEW [Audit].[RoutineLoadHistory_10]
END

GO

CREATE VIEW [Audit].[RoutineLoadHistory_10]


/******************************************************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Pulls together the load information
**
**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
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

AS


WITH RoutineLoadHistory
AS
(
SELECT LoadId
		--, CAST (LoadId AS VARCHAR (20)) AS LoadIdPath
		, CAST (LoadId AS VARCHAR (20)) AS MasterLoadId
		, ExecutionId
		, ParentLoadId
		, ExecutionGUID
		, PackageVersionGUID
		, E.PackageName
		, RoutineType
		, LoadProcess
		, LoadStatusName
		, StartTime
		, EndTime
		, Duration
		, CreatedUser
		, CreatedDate
		, UpdatedUser
		, UpdatedDate
		, 1 AS LoadRank
FROM [Audit].[RoutineLoad] E
WHERE ParentLoadId IS NULL

UNION ALL

SELECT PL.LoadId
		-- , CAST (SUBSTRING (CAST (CTE_PL.LoadIdPath AS VARCHAR (254))  + '\' + CAST (PL.LoadId  AS VARCHAR (255)), 0, 255) AS VARCHAR (20)) AS LoadIdPath
		, CTE_PL.MasterLoadId
		, PL.ExecutionId
		, PL.ParentLoadId
		, PL.ExecutionGUID
		, PL.PackageVersionGUID
		, PL.PackageName
		, PL.RoutineType
		, PL.LoadProcess
		, PL.LoadStatusName
		, PL.StartTime
		, PL.EndTime
		, PL.Duration
		, PL.CreatedUser
		, PL.CreatedDate
		, PL.UpdatedUser
		, PL.UpdatedDate
		, CTE_PL.LoadRank + 1 AS LoadRank
--SELECT *
FROM [Audit].[RoutineLoad] PL
	INNER JOIN RoutineLoadHistory CTE_PL
	ON PL.ParentLoadId = CTE_PL.LoadId
)
SELECT
	--CASE WHEN LD.LoadId = CASE WHEN LoadIdPath LIKE '%\%' THEN 
	--			SUBSTRING (LoadIdPath, 0 , CHARINDEX ('\', LoadIdPath)) 
	--			ELSE LoadIdPath 
	--			END
	--	THEN 1
	--	ELSE 0
	--	END AS IsMasterLoadPackage

	CASE WHEN LD.ParentLoadId is null THEN 1
		ELSE 0
		END AS IsMasterLoadPackage
	, LD.MasterLoadId ,

	--,CAST (CASE WHEN LoadIdPath LIKE '%\%' THEN 
	--	SUBSTRING (LoadIdPath, 0 , CHARINDEX ('\', LoadIdPath)) 
	--	ELSE LoadIdPath 
	--	END AS INT) AS MasterLoadId,
 LD.ParentLoadId, LD.LoadId,  LD.PackageName, LD.RoutineType, LD.LoadProcess, 
 REX.DatabaseName, REX.SchemaName, REX.EntityName, REX.RuleType, REX.RuleId
 , LD.LoadStatusName, RE.RoutineErrorID
 , CAST (RE.ErrorDescription AS VARCHAR (1000)) AS ErrorDescription 
 , CAST (RE.SourceName AS VARCHAR (255)) AS ErroredRoutine
 , DATEDIFF (ss,StartTime,  EndTime) as DurationInSeconds
 , LD.StartTime, LD.EndTime
FROM RoutineLoadHistory LD --[Audit].[RoutineLoad] LD
	LEFT OUTER JOIN 
		(SELECT LoadId, DatabaseName, SchemaName, EntityName, RuleType, RuleId 
			FROM [DQ].[RuleExecutionHistory] 
			GROUP BY LoadId, DatabaseName, SchemaName, EntityName, RuleType, RuleId) AS REX
	ON LD.LoadId = REX.LoadId
	LEFT OUTER JOIN [Audit].[RoutineError] RE
	ON LD.LoadId = RE.LoadId





GO
