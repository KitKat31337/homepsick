<#
.SYNOPSIS
Runs the behavior suite and collects a production command-coverage baseline.
.PARAMETER ReportDirectory
Directory for JaCoCo XML, missed-command CSV, and test/coverage summary JSON.
.EXAMPLE
./tests/Invoke-HomepsickTests.ps1 -ReportDirectory ./artifacts/coverage/local
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReportDirectory)

$ErrorActionPreference = 'Stop'
Import-Module Pester -RequiredVersion 5.7.1
$repositoryPath = Split-Path -Parent $PSScriptRoot
$reportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

$configuration = New-PesterConfiguration
$configuration.Run.Path = $PSScriptRoot
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.CodeCoverage.Enabled = $true
$configuration.CodeCoverage.Path = @(Get-ChildItem (Join-Path $repositoryPath 'src') -Recurse -File |
    Where-Object Extension -in '.ps1', '.psm1', '.psd1' | Select-Object -ExpandProperty FullName)
$configuration.CodeCoverage.OutputFormat = 'JaCoCo'
$configuration.CodeCoverage.OutputPath = Join-Path $reportPath 'coverage.xml'
# This measures a baseline, not a percentage gate. Tests still assert observable
# filesystem, link, selection, and rollback behavior independently of command hits.
$configuration.CodeCoverage.CoveragePercentTarget = 0

$result = Invoke-Pester -Configuration $configuration
$coverage = $result.CodeCoverage
$coverage.CommandsMissed | Select-Object File, Function, Class, StartLine, EndLine, Command |
    Export-Csv (Join-Path $reportPath 'missed-commands.csv') -NoTypeInformation
[ordered]@{
    Platform = [Environment]::OSVersion.Platform.ToString()
    Passed = $result.PassedCount
    Failed = $result.FailedCount
    FailedContainers = $result.FailedContainersCount
    Skipped = $result.SkippedCount
    CommandsAnalyzed = $coverage.CommandsAnalyzedCount
    CommandsExecuted = $coverage.CommandsExecutedCount
    CommandsMissed = $coverage.CommandsMissedCount
    FilesAnalyzed = $coverage.FilesAnalyzedCount
    CoveragePercent = $coverage.CoveragePercent
} | ConvertTo-Json | Set-Content (Join-Path $reportPath 'summary.json') -Encoding utf8

if ($result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0) { exit 1 }
