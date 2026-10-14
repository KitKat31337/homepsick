function Get-HomepsickSourceIssue {
    param([string]$Path, [string]$RepositoryPath)
    $obstacle = Get-HomepsickPathObstacle -Path $Path -StopAt $RepositoryPath
    if ($obstacle) { return [pscustomobject]@{ Code = 'UnsafeSource'; Message = $obstacle } }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return [pscustomobject]@{ Code = 'MissingTrackedSource'; Message = "Tracked source '$Path' is missing." } }
    if ($item.LinkType -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        try { $resolved = $item.ResolveLinkTarget($true) }
        catch { $resolved = $null }
        if (-not $resolved -or -not $resolved.Exists -or $resolved -is [IO.DirectoryInfo] -or
            -not (Test-HomepsickContainedPath -Parent $RepositoryPath -Path $resolved.FullName) -or
            (Get-HomepsickPathObstacle -Path $resolved.FullName -StopAt $RepositoryPath)) {
            return [pscustomobject]@{ Code = 'UnsafeSourceLink'; Message = "Tracked symbolic link '$Path' must resolve to a file inside the castle." }
        }
    }
    elseif ($item.PSIsContainer) {
        return [pscustomobject]@{ Code = 'UnsafeSource'; Message = "Tracked source '$Path' is a directory." }
    }
}
