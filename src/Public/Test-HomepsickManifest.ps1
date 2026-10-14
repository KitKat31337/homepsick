function Test-HomepsickManifest {
    <# .SYNOPSIS Validates a castle manifest and reports errors and warnings without modifying files. #>
    [CmdletBinding(DefaultParameterSetName = 'Castle')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Castle')][string]$CastleName,
        [Parameter(Mandatory, ParameterSetName = 'Repository')][string]$RepositoryPath,
        [System.Collections.IDictionary]$MachineFacts
    )
    if ($PSCmdlet.ParameterSetName -eq 'Castle') { $RepositoryPath = (Get-HomepsickCastle -CastleName $CastleName).CastlePath }
    $plan = Resolve-HomepsickLinkPlan -RepositoryPath $RepositoryPath -MachineFacts $MachineFacts
    [pscustomobject]@{
        RepositoryPath = $plan.RepositoryPath; HasManifest = $plan.HasManifest
        IsValid = $plan.IsValid; Errors = $plan.Errors; Warnings = $plan.Warnings
    }
}
