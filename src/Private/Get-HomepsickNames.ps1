function Get-HomepsickNames {
    [CmdletBinding()]
    param()

    $repos = Get-HomepsickPath -Repos
    if (-not (Test-Path -LiteralPath $repos -PathType Container)) { return }
    Get-ChildItem -LiteralPath $repos -Directory -Force | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName '.git')) -or
        ((Invoke-HomepsickGit -RepositoryPath $_.FullName -Arguments @('rev-parse', '--is-inside-work-tree') -AllowFailure).Output.Trim() -eq 'true')
    } | Select-Object -ExpandProperty Name
}
