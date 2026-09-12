#Requires -Version 5.1

$config = New-PesterConfiguration
$config.Run.Path = Join-Path -Path $PSScriptRoot -ChildPath 'tests'
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path -Path $PSScriptRoot -ChildPath 'test-results.xml'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = Join-Path -Path $PSScriptRoot -ChildPath 'src'
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
