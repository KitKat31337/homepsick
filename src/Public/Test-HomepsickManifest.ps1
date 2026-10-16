function Test-HomepsickManifest {
    <#
    .SYNOPSIS
    Validates a castle manifest and reports errors and warnings without modifying files.
    .PARAMETER CastleName
    Name of an installed castle to validate.
    .PARAMETER RepositoryPath
    Path to a castle repository to validate without installing it.
    .PARAMETER MachineFacts
    A complete synthetic fact context for checking selection and actual file ties.
    .OUTPUTS
    HomepsickManifestValidationResult. Validity, errors, and warnings for the castle.
    .EXAMPLE
    Test-HomepsickManifest -RepositoryPath ./dotfiles | Format-List IsValid, Errors, Warnings
    Reports structured diagnostics for a local castle without modifying its files.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Castle')]
    # String metadata is required outside module scope. The analyzer uses
    # Type.GetType, which cannot resolve private PowerShell class names.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '',
        Justification = 'String OutputType metadata names a private PowerShell class, not a CLR-resolvable type.')]
    [OutputType('HomepsickManifestValidationResult')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Castle')][string]$CastleName,
        [Parameter(Mandatory, ParameterSetName = 'Repository')][string]$RepositoryPath,
        [System.Collections.IDictionary]$MachineFacts
    )
    if ($PSCmdlet.ParameterSetName -eq 'Castle') { $RepositoryPath = (Get-HomepsickCastle -CastleName $CastleName).CastlePath }
    $plan = Resolve-HomepsickLinkPlan -RepositoryPath $RepositoryPath -MachineFacts $MachineFacts
    [HomepsickManifestValidationResult]@{
        RepositoryPath = $plan.RepositoryPath; HasManifest = $plan.HasManifest
        IsValid = $plan.IsValid; Errors = $plan.Errors; Warnings = $plan.Warnings
    }
}
