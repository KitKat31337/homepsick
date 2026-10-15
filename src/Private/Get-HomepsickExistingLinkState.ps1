function Get-HomepsickExistingLinkState {
    # Returns Missing, AlreadyLinked, ManagedLink, or Conflict without writing.
    # Ownership is inferred from the current target and declared mappings, including
    # inactive roots. A manually created link with that relationship is identical.
    # Links from other castles do not satisfy this castle's mapping check.
    param([HomepsickLinkCandidate]$Candidate, [HomepsickLinkMapping[]]$Mappings, [string]$RepositoryPath)
    $item = Get-Item -LiteralPath $Candidate.DestinationPath -Force -ErrorAction SilentlyContinue
    if (-not $item) { return 'Missing' }
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($item.LinkType -eq 'SymbolicLink') {
        $target = [IO.Path]::GetFullPath([IO.Path]::Combine([IO.Path]::GetDirectoryName($Candidate.DestinationPath), @($item.Target)[0]))
        if ([string]::Equals($target, $Candidate.SourcePath, $comparison)) { return 'AlreadyLinked' }
        foreach ($mapping in $Mappings) {
            if (-not (Test-HomepsickContainedPath -Parent $mapping.SourcePath -Path $target)) { continue }
            $relative = [IO.Path]::GetRelativePath($mapping.SourcePath, $target)
            $mapped = [IO.Path]::GetFullPath([IO.Path]::Combine($mapping.DestinationPath, $relative))
            if ([string]::Equals($mapped, $Candidate.DestinationPath, $comparison) -and
                -not (Get-HomepsickPathObstacle -Path $target -StopAt $RepositoryPath)) { return 'ManagedLink' }
        }
    }
    return 'Conflict'
}
