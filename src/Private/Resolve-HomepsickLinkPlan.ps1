function Get-HomepsickExistingLinkState {
    param([object]$Candidate, [object[]]$Mappings, [string]$RepositoryPath)
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

function Resolve-HomepsickLinkPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [System.Collections.IDictionary]$MachineFacts,
        [switch]$AllowOutsideHome
    )

    $RepositoryPath = [IO.Path]::GetFullPath($RepositoryPath)
    $homePath = [IO.Path]::GetFullPath((Get-HomePath))
    $manifest = Get-HomepsickManifest $RepositoryPath
    $detected = Get-HomepsickMachineFact -MachineFacts $MachineFacts
    $entries = @(Get-HomepsickRootSelection -Roots $manifest.Roots -Facts $detected.Facts)
    $errors = [Collections.Generic.List[object]]::new()
    foreach ($errorItem in $manifest.Errors) { $errors.Add($errorItem) }
    $candidates = [Collections.Generic.List[object]]::new()
    $mappings = [Collections.Generic.List[object]]::new()
    $addError = {
        param($Code, $Entries, $Message)
        $errors.Add([pscustomobject]@{ Severity = 'Error'; Code = $Code; Entries = @($Entries); Message = $Message })
    }
    if (-not $errors.Count -and $entries.Count) {
        $tracked = @(Get-HomepsickTrackedFile -RepositoryPath $RepositoryPath -AllRoots)
        foreach ($entry in $entries) {
            # Even skipped roots can own a link from a previous selection. Verify the
            # source-to-destination relationship before replacing such a link.
            try {
                $destinationBase = if ($entry.Target -eq 'home') { $homePath }
                    else { Resolve-HomepsickDestination -Path $manifest.Destinations[$entry.Target].Path -HomePath $homePath }
                if ($entry.Into) { $destinationBase = [IO.Path]::GetFullPath([IO.Path]::Combine($destinationBase, $entry.Into)) }
            }
            catch {
                if ($entry.Selected) { & $addError InvalidDestination $entry.Entry $_.Exception.Message }
                continue
            }
            $sourceBase = [IO.Path]::GetFullPath([IO.Path]::Combine($RepositoryPath, $entry.Source))
            $mappings.Add([pscustomobject]@{ SourcePath = $sourceBase; DestinationPath = $destinationBase })
            $entry | Add-Member DestinationPath $destinationBase
            if (-not $entry.Selected) { continue }
            $outside = -not (Test-HomepsickContainedPath -Parent $homePath -Path $destinationBase -AllowEqual)
            if ($outside -and -not $manifest.Destinations[$entry.Target].OutsideHome) {
                & $addError OutsideHomeDeclaration $entry.Entry 'Resolved destination is outside home without outsideHome: true.'
                continue
            }
            $entry | Add-Member OutsideHome $outside
            $sourceComparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
            $seenSources = [Collections.Generic.HashSet[string]]::new($sourceComparer)
            foreach ($file in $tracked) {
                if (-not $file.RepositoryRelativePath.StartsWith($entry.Source + '/', [StringComparison]::Ordinal)) { continue }
                $relative = $file.RepositoryRelativePath.Substring($entry.Source.Length + 1)
                $source = [IO.Path]::GetFullPath($file.SourcePath)
                # An unmerged Git index can enumerate several stages of one working
                # file. They are one source candidate, not independent overlay roots.
                if (-not $seenSources.Add($source)) { continue }
                $destination = [IO.Path]::GetFullPath([IO.Path]::Combine($destinationBase, $relative))
                if ($manifest.HasManifest) {
                    if (-not (Test-HomepsickRelativePath $relative)) {
                        & $addError UnsafeTrackedPath $entry.Entry "Tracked path '$relative' is not a safe portable relative path."
                        continue
                    }
                    $obstacle = Get-HomepsickPathObstacle -Path $source -StopAt $RepositoryPath
                    if ($obstacle) { & $addError UnsafeSource $entry.Entry $obstacle; continue }
                    $sourceItem = Get-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue
                    if (-not $sourceItem) { & $addError MissingTrackedSource $entry.Entry "Tracked source '$source' is missing."; continue }
                    if ($sourceItem.LinkType -or ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                        try { $resolved = $sourceItem.ResolveLinkTarget($true) }
                        catch { $resolved = $null }
                        if (-not $resolved -or -not $resolved.Exists -or $resolved -is [IO.DirectoryInfo] -or
                            -not (Test-HomepsickContainedPath -Parent $RepositoryPath -Path $resolved.FullName) -or
                            (Get-HomepsickPathObstacle -Path $resolved.FullName -StopAt $RepositoryPath)) {
                            & $addError UnsafeSourceLink $entry.Entry "Tracked symbolic link '$source' must resolve to a file inside the castle."
                            continue
                        }
                    }
                    elseif ($sourceItem.PSIsContainer) { & $addError UnsafeSource $entry.Entry "Tracked source '$source' is a directory."; continue }
                    if (Test-HomepsickContainedPath -Parent (Get-HomepsickPath -Root) -Path $destination -AllowEqual) {
                        & $addError CastleStorageDestination $entry.Entry "Destination '$destination' is inside Homepsick's castle storage."
                        continue
                    }
                    if (Test-HomepsickContainedPath -Parent $RepositoryPath -Path $destination -AllowEqual) {
                        & $addError SourceDestinationOverlap $entry.Entry "Destination '$destination' is inside the source repository."
                        continue
                    }
                }
                $candidates.Add([pscustomobject]@{
                    Entry = $entry.Entry; SourcePath = $source; RepositoryRelativePath = $file.RepositoryRelativePath
                    RelativePath = $relative; DestinationPath = $destination; Target = $entry.Target
                    Priority = $entry.Priority; CalculatedPriority = $entry.CalculatedPriority
                    PriorityOverridden = $entry.PriorityOverridden; OutsideHome = $outside
                    Allowed = (-not $outside -or [bool]$AllowOutsideHome); Status = 'Candidate'
                    ExistingState = 'Unchecked'; Reason = ''
                })
            }
        }
    }
    # Use the executing filesystem's comparison rules, even with synthetic OS facts.
    $comparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $groups = [Collections.Generic.Dictionary[string,object]]::new($comparer)
    foreach ($candidate in $candidates) {
        if (-not $groups.ContainsKey($candidate.DestinationPath)) { $groups[$candidate.DestinationPath] = [Collections.Generic.List[object]]::new() }
        $groups[$candidate.DestinationPath].Add($candidate)
    }
    foreach ($group in $groups.Values) {
        $highest = ($group | Measure-Object Priority -Maximum).Maximum
        $leaders = @($group | Where-Object Priority -eq $highest)
        foreach ($candidate in $group) {
            if ($candidate.Priority -lt $highest) {
                $candidate.Status = 'Shadowed'
                $candidate.Reason = "Higher priority $highest from $($leaders.Entry -join ', ')."
            }
            elseif ($leaders.Count -gt 1) {
                $candidate.Status = 'Tie'
                $candidate.Reason = "Equal highest priority $highest."
            }
            else { $candidate.Status = 'Winner' }
        }
        if ($leaders.Count -gt 1) { & $addError PriorityTie $leaders.Entry "Equal priority candidates for '$($leaders[0].DestinationPath)': $($leaders.Entry -join ', ')." }
    }
    $winners = @($candidates | Where-Object Status -eq Winner)
    $winnerPaths = [Collections.Generic.Dictionary[string,object]]::new($comparer)
    foreach ($candidate in $winners) { $winnerPaths.Add($candidate.DestinationPath, $candidate) }
    foreach ($candidate in $winners) {
        $ancestor = [IO.Path]::GetDirectoryName($candidate.DestinationPath)
        while ($ancestor) {
            if ($winnerPaths.ContainsKey($ancestor)) {
                $other = $winnerPaths[$ancestor]
                & $addError DestinationOverlap @($candidate.Entry, $other.Entry) "A file destination contains another file destination: '$($candidate.DestinationPath)' and '$($other.DestinationPath)'."
            }
            $ancestor = [IO.Path]::GetDirectoryName($ancestor)
        }
        $candidate.ExistingState = Get-HomepsickExistingLinkState -Candidate $candidate -Mappings $mappings -RepositoryPath $RepositoryPath
        if ($manifest.HasManifest) {
            $obstacle = Get-HomepsickPathObstacle -Path $candidate.DestinationPath
            if ($obstacle) {
                $candidate.ExistingState = 'Blocked'
                $candidate.Reason = $obstacle
                & $addError UnsafeDestination $candidate.Entry $obstacle
            }
        }
        if (-not $candidate.Allowed) { $candidate.Reason = 'Requires -AllowOutsideHome before modifying this destination.' }
        elseif ($candidate.ExistingState -eq 'Conflict') { $candidate.Reason = 'Existing destination conflicts with the proposed link.' }
    }
    [pscustomobject]@{
        RepositoryPath = $RepositoryPath; HasManifest = $manifest.HasManifest
        MachineFacts = $detected.Facts; FactNotes = $detected.Notes; Entries = $entries
        Candidates = @($candidates); Winners = $winners; RootMappings = @($mappings)
        Shadowed = @($candidates | Where-Object Status -eq Shadowed); Ties = @($candidates | Where-Object Status -eq Tie)
        Conflicts = @($winners | Where-Object { $_.ExistingState -in @('Conflict', 'Blocked') })
        Errors = @($errors); Warnings = $manifest.Warnings; IsValid = ($errors.Count -eq 0)
    }
}
