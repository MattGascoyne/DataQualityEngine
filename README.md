#DataQualityEngine

Data Quality Engine DQE is a set of routines designed to run on the SQL Server platform.

The DQE is designed as a SSIS, Master Data Services, SQL Agent and T-SQL based solution. The DQE gives you a centralised and metadata driven mechanism for managing your data profiling, validation and cleansing activities.

The DQE is simply called as a Stored Procedure and can be used at any stage in the ETL process as well as providing support for multi-step activities.

DQE has been designed to

•	Centralise data quality rules into a single repository
•	Provide a user interface to allow technically-oriented users to manage rules
•	Provide a flexible mechanism for invoking the data quality rules such that it can be easily be called at multiple points within an ETL flow
•	Capture the results of past tests and keep a record of failed DQ tests
DQE implements around 30 different types of cleansing, validation and profiling rule which fall into six broad categories:

•	Value Correction Rules
•	Expression Rules
•	Reference Rules
•	Harmonisation Rules
•	Profiling Rules
•	Transformation Rules
We have designed the DQE to be completely open source and highly configurable which allows you to fine tune the solution to your environment

Full installation instructions can be found in the Installation Guide.

