function Get-HomepsickLinkPlan {
    <#
    .SYNOPSIS
    Previews root selection, file priorities, and destination conflicts without writing files.
    .PARAMETER MachineFacts
    A complete synthetic fact context. Unspecified facts are unavailable, rather than detected.
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
