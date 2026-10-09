function Get-HomepsickCastleStatus {
    <# .SYNOPSIS Checks a castle against its upstream without changing files. #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Single')][string]$CastleName,
        [Parameter(ParameterSetName = 'All')][switch]$All
    )

    $names = if ($PSCmdlet.ParameterSetName -eq 'Single') { @($CastleName) } else { @(Get-HomepsickNames) }
    foreach ($name in $names) {
        $castle = Get-HomepsickCastle -CastleName $name
        $repo = $castle.CastlePath
        $upstream = Invoke-HomepsickGit -RepositoryPath $repo -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}') -AllowFailure
        $state = 'Uncheckable'
        if ($upstream.ExitCode -eq 0) {
            $remote = (Invoke-HomepsickGit -RepositoryPath $repo -Arguments @('config', '--get', "branch.$((Invoke-HomepsickGit -RepositoryPath $repo -Arguments @('branch', '--show-current')).Output.Trim()).remote") -AllowFailure).Output.Trim()
            $remoteRef = (Invoke-HomepsickGit -RepositoryPath $repo -Arguments @('rev-parse', '--symbolic-full-name', '@{upstream}')).Output.Trim()
            $remoteBranch = $remoteRef -replace '^refs/remotes/[^/]+/', ''
            $remoteHead = (Invoke-HomepsickGit -RepositoryPath $repo -Arguments @('ls-remote', '--heads', $remote, "refs/heads/$remoteBranch") -AllowFailure).Output
            if ($remoteHead -match '^([0-9a-f]+)\s') {
                $remoteHash = $Matches[1]
                $localHash = (Invoke-HomepsickGit -RepositoryPath $repo -Arguments @('rev-parse', 'HEAD')).Output.Trim()
                if ($remoteHash -eq $localHash) {
                    $changes = (Invoke-HomepsickGit -RepositoryPath $repo -Arguments @('status', '--porcelain')).Output
                    $state = if ($changes) { 'Modified' } else { 'Current' }
                }
                elseif ((Invoke-HomepsickGit -RepositoryPath $repo -Arguments @('cat-file', '-e', $remoteHash) -AllowFailure).ExitCode -eq 0) {
                    $base = (Invoke-HomepsickGit -RepositoryPath $repo -Arguments @('merge-base', $remoteHash, $localHash) -AllowFailure).Output.Trim()
                    $state = if ($base -eq $remoteHash) { 'Ahead' } elseif ($base -eq $localHash) { 'Behind' } else { 'Diverged' }
                }
                else { $state = 'Behind' }
            }
        }
        [pscustomobject]@{ CastleName = $name; Status = $state; Upstream = $upstream.Output.Trim(); Path = $repo }
    }
}
