USE [SSISDB];
GO


-- CONFIGURATION - GLOBAL DEFINITIONS - set the environment configurations here
DECLARE @EnvironmentName SYSNAME = N'$(EnvironmentName)'; --  DQEParameters;
DECLARE @FolderName SYSNAME =  N'$(SSISCatalogFolderName)';  -- DataQualityEngine;
DECLARE @ProjectName SYSNAME = N'$(SSISCatalogProjectName)'; -- DataQualityEngine;
DECLARE @MDSSERVER SYSNAME = N'$(MDSservername)'; -- EDIT -- Your MDS Server Instance
DECLARE @MDSDB SYSNAME = N'$(MDSDatabaseName)'; -- EDIT: Your MDS Database name
DECLARE @DataQualityServer SYSNAME =  N'$(DataQualityDBservername)';  -- EDIT: The Server you have installed your DataQualityDB
DECLARE @DataQualityDB SYSNAME =  N'$(DQEDatabaseName)'; 
DECLARE @AuditServer SYSNAME =  N'$(DataQualityDBservername)'; -- EDIT: The Server you have installed your DataQualityDB
DECLARE @AuditDB SYSNAME =  N'$(DQEDatabaseName)';  

-- get the ids for the configure names
-- no need to touch this code
DECLARE @FolderID BIGINT = (SELECT F.folder_id FROM [catalog].folders AS F WHERE F.name = @FolderName);
DECLARE @ProjectID BIGINT = (SELECT P.project_id FROM [catalog].projects AS P WHERE P.name = @ProjectName AND P.folder_id = @FolderID);
 
-- CONFIGURATION - PARAMETERS
-- this table will hold all environment variables to be defined and mapped
-- there are two ways to go about defining what needs to be mapped, so check out the options below
DECLARE @Variables TABLE
(
    MyKey INT IDENTITY (1, 1) NOT NULL PRIMARY KEY CLUSTERED, /* Iteration Index, don't worry about this. */
 
    EnvironmentVariableName     SYSNAME         NOT NULL,       /* Name of the new environment variable. */
    EnvironmentVariableValue    SQL_VARIANT     NOT NULL,       /* Use N' (unicode) notation or CAST for strings to ensure you get an NVARCHAR. Use CAST with numeric values to ensure you get the correct type. */
    EnvironmentVariableType     SYSNAME         NOT NULL,       /* The SSIS Variable Type (String, Int32, DateTime...) */
    TargetObjectType            SYSNAME         NOT NULL,       /* What to map this variable to. Use "Project" or "Package" */
    TargetObjectName            SYSNAME         NOT NULL,       /* When mapping to a project use the Project Name. When mapping to a package use the Package Name. */
    TargetParameterName         SYSNAME         NOT NULL,       /* Name of the parameter to map the environment variable to. */
 
    /* Duplicate environment variable names are not allowed. */
    UNIQUE (EnvironmentVariableName)
)
 
BEGIN

    INSERT INTO @Variables (EnvironmentVariableName, EnvironmentVariableValue, EnvironmentVariableType, TargetObjectType, TargetObjectName, TargetParameterName)
    VALUES
	('DataQualityDB_ConnectionString' ,'Data Source=' + @DataQualityServer + ';Initial Catalog='+ @DataQualityDB +';Integrated Security=SSPI;' ,'String','Project',@ProjectName,'DataQualityDB_ConnectionString'),
	('MDSDB_ConnectionString' ,'Data Source=' + @MDSSERVER + ';Initial Catalog=' + @MDSDB + ';Provider=SQLNCLI11.1;Integrated Security=SSPI;Auto Translate=False' ,'String','Project',@ProjectName,'MDSDB_ConnectionString'),
	('AuditDB_ConnectionString' ,'Data Source=' + @AuditServer + ';Initial Catalog='+ @AuditDB +';Provider=SQLNCLI11.1;Integrated Security=SSPI;Auto Translate=False' ,'String','Project',@ProjectName,'AuditDB_ConnectionString'),
	('DomainName','DQEDomain','String','Project',@ProjectName,'DomainName'),
	('ParentLoadId', '0' ,'Int32','Project',@ProjectName,'ParentLoadId'),
	('RuleEntityAssociationCode','0','String','Project',@ProjectName,'RuleEntityAssociationCode')
    ;
END
 
-- END OF CONFIGURATION - everything below should work on its own
 
-- create the environment now
IF NOT EXISTS (SELECT * FROM catalog.environments WHERE name = @EnvironmentName AND folder_id =@FolderID)
BEGIN
    EXECUTE [catalog].[create_environment]
        @environment_name = @EnvironmentName,
        @environment_description= N'',
        @folder_name = @FolderName;
END
DECLARE @EnvironmentID INT = (SELECT environment_id FROM [catalog].environments WHERE name = @EnvironmentName AND folder_id =@FolderID);
 
 
-- loop variables
DECLARE @VariableKey INT, @LastVariableKey INT;
DECLARE @VariableName SYSNAME, @VariableValue SQL_VARIANT, @VariableType SYSNAME, @TargetObjectType SYSNAME, @TargetObjectName SYSNAME, @TargetParameterName SYSNAME;
 
-- create all the variables in the environment now
SET @VariableKey = 1;
SET @LastVariableKey = (SELECT MAX(MyKey) FROM @Variables);
WHILE (@VariableKey <= @LastVariableKey)
BEGIN
 
    SELECT
        @VariableName = EnvironmentVariableName,
        @VariableValue = EnvironmentVariableValue,
        @VariableType = EnvironmentVariableType
    FROM
        @Variables
    WHERE
        MyKey = @VariableKey;
 
	if @VariableType <> 'int32'
	begin
    IF NOT EXISTS (SELECT * FROM [catalog].environment_variables AS V WHERE V.name = @VariableName AND V.environment_id = @EnvironmentID)
    BEGIN
        EXEC [catalog].[create_environment_variable]
            @variable_name = @VariableName,
            @sensitive = False,
            @description = N'',
            @environment_name = @EnvironmentName,
            @folder_name = @FolderName,
            @value = @VariableValue,
            @data_type = @VariableType
    END
	end
	
	if @VariableType = 'int32'
	begin
    IF NOT EXISTS (SELECT * FROM [catalog].environment_variables AS V WHERE V.name = @VariableName AND V.environment_id = @EnvironmentID)
    BEGIN
		declare @intVariableValue INT
		SET @intVariableValue = CAST (@VariableValue AS INT)
        EXEC [catalog].[create_environment_variable]
            @variable_name = @VariableName,
            @sensitive = False,
            @description = '',
            @environment_name = @EnvironmentName,
            @folder_name = @FolderName,
            @value = @intVariableValue, 
            @data_type = @VariableType
	END
	end


    SET @VariableKey += 1;
 
END
 
-- associate the project with the environment
-- this will be done with a relative reference as the Environment is in the same folder as the Project
DECLARE @ReferenceID BIGINT = NULL;
IF NOT EXISTS (SELECT R.reference_id FROM [catalog].environment_references AS R WHERE R.environment_folder_name IS NULL AND R.environment_name = @EnvironmentName AND R.project_id = @ProjectID)
BEGIN
    EXECUTE [catalog].[create_environment_reference]
        @environment_name = @EnvironmentName,
        @reference_id = @ReferenceID OUTPUT,
        @project_name = @ProjectName,
        @folder_name = @FolderName,
        @reference_type = R
END
 
-- associate every Environment Variable with the proper parameter in the Project
SET @VariableKey = 1;
SET @LastVariableKey = (SELECT MAX(MyKey) FROM @Variables);
 
WHILE @VariableKey <= @LastVariableKey
BEGIN
 
    SELECT
        @VariableName = V.EnvironmentVariableName,
        @TargetObjectType = V.TargetObjectType,
        @TargetObjectName = V.TargetObjectName,
        @TargetParameterName = V.TargetParameterName
    FROM
        @Variables AS V
    WHERE
        MyKey = @VariableKey;
 
    DECLARE @ObjectTypeCode SMALLINT = (CASE WHEN @TargetObjectType = 'Project' THEN 20 ELSE 30 END); /* 20 = "Project Mapping", 30 = "Package Mapping" */

    IF NOT EXISTS (SELECT * FROM [catalog].object_parameters AS P WHERE
        P.project_id = @ProjectID AND
        P.object_type = @ObjectTypeCode AND
        P.object_name = @TargetObjectName AND
        P.parameter_name = @TargetParameterName AND
        P.value_type = 'R' AND /* R = Referenced, V = Value */
        P.referenced_variable_name = @VariableName)
    BEGIN

        EXECUTE [catalog].[set_object_parameter_value]
            @object_type = @ObjectTypeCode,
            @parameter_name = @TargetParameterName,
            @object_name = @TargetObjectName,
            @folder_name = @FolderName,
            @project_name = @ProjectName,
            @value_type = R,
            @parameter_value = @VariableName
    END
	
 
    SET @VariableKey += 1;
END


