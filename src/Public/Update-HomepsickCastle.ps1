function Update-HomepsickCastle {
    <# .SYNOPSIS Pulls castle updates and initializes nested submodules. #>
    [CmdletBinding(DefaultParameterSetName = 'All', SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Single')][string]$CastleName,
        [Parameter(ParameterSetName = 'All')][switch]$All,
        [switch]$Link,
        [switch]$Batch,
        [switch]$AllowOutsideHome
    )

    $names = if ($PSCmdlet.ParameterSetName -eq 'Single') { @($CastleName) } else { @(Get-HomepsickNames) }
    foreach ($name in $names) {
        $castle = Get-HomepsickCastle -CastleName $name
        if (-not $PSCmdlet.ShouldProcess($castle.CastlePath, 'Pull castle updates')) { continue }
        $hadManifest = Test-HomepsickEntry (Join-Path $castle.CastlePath 'homepsick.json')
        $beforePlan = if ($hadManifest) { Resolve-HomepsickLinkPlan -RepositoryPath $castle.CastlePath }
        $before = (Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('rev-parse', 'HEAD') -AllowFailure).Output.Trim()
        $castle.Update()
        $after = (Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('rev-parse', 'HEAD') -AllowFailure).Output.Trim()
        $hasManifest = Test-HomepsickEntry (Join-Path $castle.CastlePath 'homepsick.json')
        $newFiles = if ($before -and $after -and $before -ne $after -and ($hadManifest -or $hasManifest)) {
            $afterPlan = Resolve-HomepsickLinkPlan -RepositoryPath $castle.CastlePath
            $selectedRoots = @(@($beforePlan.Entries) + @($afterPlan.Entries) | Where-Object Selected | Select-Object -ExpandProperty Source -Unique)
            $changes = (Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('diff', '--name-only', '-z', $before, $after)).Output -split "`0"
            @($changes | Where-Object {
                $changedPath = $_
                $changedPath -eq 'homepsick.json' -or @($selectedRoots | Where-Object {
                    $changedPath -eq $_ -or $changedPath.StartsWith($_ + '/', [StringComparison]::Ordinal)
                }).Count -gt 0
            }).Count -gt 0
        }
        elseif ($before -and $after -and $before -ne $after) {
            (Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('diff', '--name-only', '--diff-filter=AR', $before, $after, '--', 'home')).Output
        }
        if ($newFiles -and ($hadManifest -or $hasManifest -or (Test-Path -LiteralPath $castle.CastleSymRoot -PathType Container))) {
            if ($Link) { Enable-HomepsickCastle -CastleName $name -Batch:$Batch -AllowOutsideHome:$AllowOutsideHome }
            elseif (-not $Batch -and $PSCmdlet.ShouldContinue("Link new files from '$name'?", 'Castle updated')) {
                Enable-HomepsickCastle -CastleName $name -AllowOutsideHome:$AllowOutsideHome
            }
        }
    }
}
