function Get-HomepsickPathObstacle {
    # Returns the first unsafe existing ancestor as a message, or nothing if safe.
    # Missing directories are allowed; links, reparse points, and files must not
    # redirect future writes. StopAt bounds source checks to the castle boundary.
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
