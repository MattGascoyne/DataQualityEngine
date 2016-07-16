USE SSISDB
GO

DECLARE @FolderName SYSNAME = N'$(SSISCatalogFolderName)';
DECLARE @JobName SYSNAME = N'$(SQLJobName)';
DECLARE @ProjName SYSNAME = N'$(SSISCatalogProjectName)';
DECLARE @EnvName SYSNAME = N'$(EnvironmentName)';


PRINT 'Deleting the project : ' + @ProjName 
IF EXISTS (SELECT 1 FROM internal.projects WHERE name = @ProjName)
	EXEC [SSISDB].[catalog].[delete_project] @project_name=@ProjName, @folder_name=@FolderName

PRINT 'Deleting the associated environment : ' + @EnvName 
IF EXISTS (SELECT 1 FROM SSISDB.[internal].[environments] e 
	JOIN SSISDB.[internal].[folders] f ON e.folder_id = f.folder_id
	WHERE e.environment_name = @EnvName  AND f.name = @FolderName )
	EXEC [SSISDB].[catalog].[delete_environment] @environment_name=@EnvName, @folder_name=@FolderName

PRINT 'Deleting the folder : ' + @FolderName 
IF EXISTS (SELECT 1 FROM internal.folders WHERE name = @FolderName)
	EXEC [SSISDB].[catalog].[delete_folder] @folder_name=@FolderName

PRINT 'Deleting the SQL job : ' + @JobName 
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)  
	EXEC msdb.dbo.sp_delete_job @job_name = @JobName , @delete_history=0, @delete_unused_schedule=0
GO