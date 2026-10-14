function Get-HomepsickLinkPlan {
    <#
    .SYNOPSIS
    Previews root selection, file priorities, and destination conflicts without writing files.
    .PARAMETER CastleName
    Name of an installed castle to inspect.
    .PARAMETER RepositoryPath
    Path to a castle repository to inspect without installing it.
    .PARAMETER MachineFacts
    A complete synthetic fact context. Unspecified facts are unavailable, rather than detected.
    .PARAMETER AllowOutsideHome
    Marks explicitly declared external destinations as authorized in the preview; writes no files.
    .EXAMPLE
    Get-HomepsickLinkPlan -CastleName dotfiles -MachineFacts @{ os = 'windows'; windowsRelease = '11'; windowsEdition = 'pro' }
    Inspects Windows 11 Pro selection, priorities, and conflicts using synthetic facts.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Castle')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Castle')][string]$CastleName,
        [Parameter(Mandatory, ParameterSetName = 'Repository')][string]$RepositoryPath,
        [System.Collections.IDictionary]$MachineFacts,
        [switch]$AllowOutsideHome
    )
    if ($PSCmdlet.ParameterSetName -eq 'Castle') { $RepositoryPath = (Get-HomepsickCastle -CastleName $CastleName).CastlePath }
    Resolve-HomepsickLinkPlan -RepositoryPath $RepositoryPath -MachineFacts $MachineFacts -AllowOutsideHome:$AllowOutsideHome
}
