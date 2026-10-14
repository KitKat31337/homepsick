function Test-HomepsickRelativePath {
    param([object]$Path)
    if ($Path -isnot [string] -or [string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '[\\:\x00-\x1f*?\[\]<>"|]' -or $Path.StartsWith('/')) { return $false }
    foreach ($part in ($Path -split '/')) {
        if ($part -in @('', '.', '..', '.git') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            $part -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)') { return $false }
    }
    return $true
}

function Test-HomepsickContainedPath {
    param([string]$Parent, [string]$Path, [switch]$AllowEqual)
    $relative = [IO.Path]::GetRelativePath($Parent, $Path)
    if ($relative -eq '.') { return [bool]$AllowEqual }
    return (-not [IO.Path]::IsPathRooted($relative) -and $relative -ne '..' -and
        -not $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar))
}

function Get-HomepsickPathObstacle {
    param([string]$Path, [string]$StopAt, [switch]$IncludeLeaf)
    $current = if ($IncludeLeaf) { $Path } else { [IO.Path]::GetDirectoryName($Path) }
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.LinkType -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
            return "Symbolic link or reparse point in path: $current"
        }
        if ($item -and -not $item.PSIsContainer) { return "Parent path is a file: $current" }
        if ($StopAt -and $current -eq $StopAt) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Resolve-HomepsickDestination {
    param([string]$Path, [string]$HomePath)
    if ($Path.StartsWith('~/')) { return [IO.Path]::GetFullPath([IO.Path]::Combine($HomePath, $Path.Substring(2))) }
    if (($Path -match '^[A-Za-z]:/' -and -not $IsWindows) -or ($Path.StartsWith('/') -and $IsWindows)) {
        throw "Destination '$Path' is an absolute path for another platform."
    }
    return [IO.Path]::GetFullPath($Path)
}
