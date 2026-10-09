function Get-HomepsickTrackedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [string]$Prefix = ''
    )

    # --stage distinguishes Git submodules (mode 160000) from ordinary files.
    # NUL separators preserve spaces and newlines in file names.
    $entries = (Invoke-HomepsickGit -RepositoryPath $RepositoryPath -Arguments @('ls-files', '--stage', '-z')).Output
    foreach ($entry in ($entries -split "`0")) {
        if (-not $entry) { continue }
        if ($entry -notmatch '^(?<mode>\d+) [0-9a-f]+ \d+\t(?<path>.*)$') { continue }
        $relative = ($Prefix + $Matches.path).Replace('/', [IO.Path]::DirectorySeparatorChar)
        if ($Matches.mode -eq '160000') {
            $submodule = Join-Path $RepositoryPath $Matches.path
            if (Test-Path -LiteralPath $submodule -PathType Container) {
                Get-HomepsickTrackedFile -RepositoryPath $submodule -Prefix ($Prefix + $Matches.path + '/')
            }
        }
        elseif ($relative.StartsWith(('home' + [IO.Path]::DirectorySeparatorChar), [StringComparison]::Ordinal)) {
            $path = $relative.Substring(5)
            [pscustomobject]@{ RelativePath = $path; SourcePath = (Join-Path $RepositoryPath $Matches.path) }
        }
    }
}
