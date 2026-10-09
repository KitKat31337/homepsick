function Invoke-HomepsickCastleRefresh {
    <# .SYNOPSIS Pulls castles whose last fetch is older than the requested number of days. #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Single')][string]$CastleName,
        [Parameter(ParameterSetName = 'All')][switch]$All,
        [ValidateRange(0, 36500)][int]$Days = 7,
        [switch]$Pull,
        [switch]$Batch,
        [switch]$Link
    )

    $names = if ($PSCmdlet.ParameterSetName -eq 'Single') { @($CastleName) } else { @(Get-HomepsickNames) }
    foreach ($name in $names) {
        $castle = Get-HomepsickCastle -CastleName $name
        $fetchPath = (Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('rev-parse', '--git-path', 'FETCH_HEAD')).Output.Trim()
        if (-not [IO.Path]::IsPathRooted($fetchPath)) { $fetchPath = Join-Path $castle.CastlePath $fetchPath }
        $fetch = Get-Item -LiteralPath $fetchPath -ErrorAction SilentlyContinue
        if ($fetch -and $fetch.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddDays(-$Days)) {
            Write-Verbose "Castle '$name' is fresh."
            continue
        }
        if ($Pull) { Update-HomepsickCastle -CastleName $name -Link:$Link -Batch:$Batch }
        elseif (-not $Batch -and $PSCmdlet.ShouldContinue("Castle '$name' is outdated. Pull it?", 'Refresh castle')) {
            Update-HomepsickCastle -CastleName $name -Link:$Link
        }
        elseif (-not $Batch -and $fetch) {
            # Like homeshick, defer another interactive reminder after declining.
            $fetch.LastWriteTimeUtc = [DateTime]::UtcNow
        }
    }
}
