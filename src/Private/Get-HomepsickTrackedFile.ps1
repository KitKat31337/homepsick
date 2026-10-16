function Get-HomepsickTrackedFile {
    # Enumerates Git-tracked files, recursively through initialized submodules.
    # Returns HomepsickTrackedFile (home-relative) for legacy callers; AllRoots
    # returns HomepsickRepositoryFile with the full repository-relative path.
    # Index stages remain visible here; the planner deduplicates source candidates.
    [CmdletBinding()]
    [OutputType([HomepsickTrackedFile], [HomepsickRepositoryFile])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [string]$Prefix = '',
        [switch]$AllRoots
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
                Get-HomepsickTrackedFile -RepositoryPath $submodule -Prefix ($Prefix + $Matches.path + '/') -AllRoots:$AllRoots
            }
        }
        elseif ($AllRoots -or $relative.StartsWith(('home' + [IO.Path]::DirectorySeparatorChar), [StringComparison]::Ordinal)) {
            $path = if ($AllRoots) { $relative } else { $relative.Substring(5) }
            if ($AllRoots) {
                [HomepsickRepositoryFile]@{
                    RelativePath = $path; SourcePath = (Join-Path $RepositoryPath $Matches.path)
                    RepositoryRelativePath = ($Prefix + $Matches.path)
                }
            }
            else { [HomepsickTrackedFile]@{ RelativePath = $path; SourcePath = (Join-Path $RepositoryPath $Matches.path) } }
        }
    }
}
