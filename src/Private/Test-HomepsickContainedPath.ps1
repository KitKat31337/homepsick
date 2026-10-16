function Test-HomepsickContainedPath {
    # Returns lexical containment using native filesystem path comparison.
    # Symlink/reparse traversal is checked separately by Get-HomepsickPathObstacle.
    param([string]$Parent, [string]$Path, [switch]$AllowEqual)
    $relative = [IO.Path]::GetRelativePath($Parent, $Path)
    if ($relative -eq '.') { return [bool]$AllowEqual }
    return (-not [IO.Path]::IsPathRooted($relative) -and $relative -ne '..' -and
        -not $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar))
}
