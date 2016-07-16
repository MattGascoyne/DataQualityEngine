USE [DataQualityDB]
GO

IF EXISTS (SELECT 1 FROM [INFORMATION_SCHEMA].[ROUTINES] 
				WHERE SPECIFIC_NAME = 'sExecuteSSISDataQualityEngine'
				AND SPECIFIC_SCHEMA = 'DQ') 
BEGIN 
	DROP PROC [DQ].[sExecuteSSISDataQualityEngine]
END

GO

CREATE proc [DQ].[sExecuteSSISDataQualityEngine]
@PackageName varchar (255), -- 'MasterController.dtsx'
@FolderName varchar (255),-- 'DataQualityEngine'
@ProjectName varchar (255), -- 'DataQualityEngine'
@DQDomainName varchar (255), -- 'DataQualityEngine'
@EnvironmentName  varchar (255), -- 'Production'
@RuleEntityAssociationCode varchar (255) = 'Ignore' -- The optional code of a stand alone rule that you want to execute

AS

/******************************************************************************
***********************		DEPRECATED ****************************************
**     Author:       Dartec Systems (Matt Gascoyne)
**     Created Date: 15/11/2015
**     Desc: Simple proc to execute the MasterDataQuality package.
			This routine has been included purely for illustrative purposes and should be hardened to suit your production requirements.
			Useful online resources are plentiful, here are a few...
			http://thinknook.com/execute-ssis-via-stored-procedure-ssis-2012-2012-08-13/
			http://blog.sqlauthority.com/2015/08/06/sql-server-a-stored-procedure-for-executing-ssis-packages-in-the-ssis-catalog-notes-from-the-field-092/
			http://sqlblog.com/blogs/jamie_thomson/archive/2012/07/18/execution-statuses-ssis.aspx
**
** EXAMPLE:
EXEC [DQ].[sExecuteSSISDataQualityEngine]
@PackageName = 'MasterController.dtsx'
, @FolderName = 'DataQualityEngine'
, @ProjectName = 'DataQualityEngine'
, @EnvironmentName = 'Production'
, @RuleEntityAssociationCode = 23 -- Optional, the stand-alone code of the rule you want to run 

**     Return values:
**
**     Called by:
**             
**     Parameters:
**     Input
**     ----------
--					
**
**     Output
**     ----------

** 
*******************************************************************************
**     Change History
*******************************************************************************
**     By:    Date:         Description:
**     ---    --------      -----------------------------------------------------------
**     MG     01/03/2016    Release 1.0.3
*******************************************************************************/

DECLARE @exec_id BIGINT
		, @ReferenceId INT
		, @environmentId INT


SELECT  @ReferenceId = reference_id
  FROM  SSISDB.[catalog].environment_references er
        JOIN SSISDB.[catalog].projects p ON p.project_id = er.project_id
 WHERE  er.environment_name = @EnvironmentName
   AND  p.name              = @ProjectName;

/**Set SSIS environment variables at run time**/
SELECT   @environmentId = environment_id
FROM  SSISDB.[catalog].environments e
		INNER JOIN SSISDB.[catalog].folders f
			ON  e.folder_id = f.folder_id
		INNER JOIN SSISDB.[catalog].projects p 
			ON p.folder_id = f.folder_id
	WHERE  e.name = @EnvironmentName -- 'DQEParameters'
	AND  p.name = @ProjectName --'DataQualityEngine'
	AND f.name = @FolderName -- 'DataQualityEngine'

/* Set the DQ Domain that you want to execute*/
UPDATE SSISDB.[internal].[environment_variables] 
SET value = @DQDomainName
WHERE Name = 'DomainName'
AND environment_id = @environmentId


/* Set the stand-alone rule you want to execute. 
Unless explicitly specified this will be set to ignore which is allow the DQE to execute the full domain*/
UPDATE SSISDB.[internal].[environment_variables] 
SET value = @RuleEntityAssociationCode
WHERE Name = 'RuleEntityAssociationCode'
AND environment_id = @environmentId

EXEC [SSISDB].[catalog].[create_execution] 
    @package_name=@PackageName,     --SSIS package name TABLE:(SELECT * FROM [SSISDB].internal.packages)
    @folder_name=@FolderName, --Folder were the package lives TABLE:(SELECT * FROM [SSISDB].internal.folders)
    @project_name=@ProjectName,--Project name were SSIS package lives TABLE:(SELECT * FROM [SSISDB].internal.projects)
    @use32bitruntime=FALSE, 
    @reference_id=@ReferenceId,             --Environment reference, if null then no environment configuration is applied 
    @execution_id=@exec_id OUTPUT   --The paramter is outputed and contains the execution_id of your SSIS execution context.

SELECT @exec_id
	
EXEC [SSISDB].[catalog].[start_execution] @exec_id
	

GO

