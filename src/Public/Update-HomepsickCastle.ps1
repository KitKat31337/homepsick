function Update-HomepsickCastle {
    <# .SYNOPSIS Pulls castle updates and initializes nested submodules. #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Single')][string]$CastleName,
        [Parameter(ParameterSetName = 'All')][switch]$All,
        [switch]$Link,
        [switch]$Batch
    )

    $names = if ($PSCmdlet.ParameterSetName -eq 'Single') { @($CastleName) } else { @(Get-HomepsickNames) }
    foreach ($name in $names) {
        $castle = Get-HomepsickCastle -CastleName $name
        $before = (Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('rev-parse', 'HEAD') -AllowFailure).Output.Trim()
        $castle.Update()
        $after = (Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('rev-parse', 'HEAD') -AllowFailure).Output.Trim()
        $newFiles = if ($before -and $after -and $before -ne $after) {
            (Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('diff', '--name-only', '--diff-filter=AR', $before, $after, '--', 'home')).Output
        }
        if ($newFiles -and (Test-Path -LiteralPath $castle.CastleSymRoot -PathType Container)) {
            if ($Link) { Enable-HomepsickCastle -CastleName $name -Batch:$Batch }
            elseif (-not $Batch -and $PSCmdlet.ShouldContinue("Link new files from '$name'?", 'Castle updated')) {
                Enable-HomepsickCastle -CastleName $name
            }
        }
    }
}
