function Resolve-HomepsickLinkPlan {
    # Shared, read-only engine for preview, validation, tracking, and linking.
    # Returns a HomepsickLinkPlan with selection reasons, all candidates, resolved
    # winners, and diagnostics. Errors invalidate the entire castle's execution.
    [CmdletBinding()]
    [OutputType([HomepsickLinkPlan])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [System.Collections.IDictionary]$MachineFacts,
        [switch]$AllowOutsideHome
    )

    $RepositoryPath = [IO.Path]::GetFullPath($RepositoryPath)
    $homePath = [IO.Path]::GetFullPath((Get-HomePath))
    $manifest = Get-HomepsickManifest $RepositoryPath
    $warnings = [Collections.Generic.List[HomepsickDiagnostic]]::new()
    foreach ($warning in $manifest.Warnings) { $warnings.Add($warning) }
    $detected = Get-HomepsickMachineFact -MachineFacts $MachineFacts
    $entries = @(Get-HomepsickRootSelection -Roots $manifest.Roots -Facts $detected.Facts)
    $errors = [Collections.Generic.List[HomepsickDiagnostic]]::new()
    foreach ($errorItem in $manifest.Errors) { $errors.Add($errorItem) }
    $candidates = [Collections.Generic.List[HomepsickLinkCandidate]]::new()
    $mappings = [Collections.Generic.List[HomepsickLinkMapping]]::new()
    $addError = {
        param($Code, $Entries, $Message)
        $errors.Add([HomepsickDiagnostic]@{
            Severity = 'Error'; Code = $Code; Entries = @($Entries); Message = $Message
        })
    }
    # Build candidates from the index, never a filesystem walk. Empty or skipped
    # sources still get useful diagnostics without making untracked files linkable.
    if (-not $errors.Count -and $entries.Count) {
        $tracked = @(Get-HomepsickTrackedFile -RepositoryPath $RepositoryPath -AllRoots)
        if ($manifest.HasManifest) {
            foreach ($root in @($manifest.Roots | Where-Object { -not $_.Implicit })) {
                $sourcePath = [IO.Path]::Combine($RepositoryPath, $root.Source)
                $sourcePrefix = $root.Source + '/'
                $linkable = @($tracked | Where-Object {
                    if ($_.RepositoryRelativePath.StartsWith($sourcePrefix, [StringComparison]::Ordinal)) {
                        $relativePath = $_.RepositoryRelativePath.Substring($sourcePrefix.Length)
                        (Test-HomepsickRelativePath $relativePath) -and
                            $null -eq (Get-HomepsickSourceIssue -Path $_.SourcePath -RepositoryPath $RepositoryPath)
                    }
                })
                if ((Test-Path -LiteralPath $sourcePath -PathType Container) -and -not $linkable.Count) {
                    $warnings.Add([HomepsickDiagnostic]@{
                        Severity = 'Warning'; Code = 'NoTrackedFiles'; Entries = @($root.Entry)
                        Message = "Source directory '$($root.Source)' has no Git-tracked linkable files."
                    })
                }
            }
        }
        $environmentDestinations = @{}
        # Resolve active entries first so inactive roots sharing an active named
        # target can still prove ownership without looking up inactive variables.
        $orderedEntries = @($entries | Where-Object Selected) + @($entries | Where-Object { -not $_.Selected })
        foreach ($entry in $orderedEntries) {
            # Record current mappings for inactive roots too. Existing-link ownership
            # is inferred from today's declarations and target, without stored history.
            try {
                $destinationBase = if ($entry.Target -eq 'home') {
                    $homePath
                }
                else {
                    $declaration = $manifest.Destinations[$entry.Target]
                    if ($declaration.EnvironmentVariable) {
                        if (-not $environmentDestinations.ContainsKey($entry.Target)) {
                            if (-not $entry.Selected) { continue }
                            $environmentDestinations[$entry.Target] = Resolve-HomepsickDestination -Path $declaration.Path -HomePath $homePath
                        }
                        $environmentDestinations[$entry.Target]
                    }
                    else { Resolve-HomepsickDestination -Path $declaration.Path -HomePath $homePath }
                }
                if ($entry.Into) {
                    $destinationBase = [IO.Path]::GetFullPath([IO.Path]::Combine($destinationBase, $entry.Into))
                }
            }
            catch {
                if ($entry.Selected) { & $addError InvalidDestination $entry.Entry $_.Exception.Message }
                continue
            }
            $sourceBase = [IO.Path]::GetFullPath([IO.Path]::Combine($RepositoryPath, $entry.Source))
            $mappings.Add([HomepsickLinkMapping]@{ SourcePath = $sourceBase; DestinationPath = $destinationBase })
            $entry.DestinationPath = $destinationBase
            if (-not $entry.Selected) { continue }
            $outside = -not (Test-HomepsickContainedPath -Parent $homePath -Path $destinationBase -AllowEqual)
            if ($outside -and -not $manifest.Destinations[$entry.Target].OutsideHome) {
                & $addError OutsideHomeDeclaration $entry.Entry 'Resolved destination is outside home without outsideHome: true.'
                continue
            }
            $entry.OutsideHome = $outside
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
                    $sourceIssue = Get-HomepsickSourceIssue -Path $source -RepositoryPath $RepositoryPath
                    if ($sourceIssue) {
                        & $addError $sourceIssue.Code $entry.Entry $sourceIssue.Message
                        continue
                    }
                    if (Test-HomepsickContainedPath -Parent (Get-HomepsickPath -Root) -Path $destination -AllowEqual) {
                        & $addError CastleStorageDestination $entry.Entry "Destination '$destination' is inside Homepsick's castle storage."
                        continue
                    }
                    if (Test-HomepsickContainedPath -Parent $RepositoryPath -Path $destination -AllowEqual) {
                        & $addError SourceDestinationOverlap $entry.Entry "Destination '$destination' is inside the source repository."
                        continue
                    }
                }
                $candidates.Add([HomepsickLinkCandidate]@{
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
    # Arbitrate only within this castle. Use the executing filesystem's comparison
    # rules even with synthetic OS facts; order must never break a highest-score tie.
    $comparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $groups = [Collections.Generic.Dictionary[string, Collections.Generic.List[HomepsickLinkCandidate]]]::new($comparer)
    foreach ($candidate in $candidates) {
        if (-not $groups.ContainsKey($candidate.DestinationPath)) {
            $groups[$candidate.DestinationPath] = [Collections.Generic.List[HomepsickLinkCandidate]]::new()
        }
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
        if ($leaders.Count -gt 1) {
            $message = "Equal priority candidates for '$($leaders[0].DestinationPath)': $($leaders.Entry -join ', ')."
            & $addError PriorityTie $leaders.Entry $message
        }
    }
    # A winning file cannot also be an ancestor directory of another winner.
    # Index paths once, then walk ancestors rather than comparing every file pair.
    $winners = @($candidates | Where-Object Status -eq Winner)
    $winnerPaths = [Collections.Generic.Dictionary[string, HomepsickLinkCandidate]]::new($comparer)
    foreach ($candidate in $winners) { $winnerPaths.Add($candidate.DestinationPath, $candidate) }
    foreach ($candidate in $winners) {
        $ancestor = [IO.Path]::GetDirectoryName($candidate.DestinationPath)
        while ($ancestor) {
            if ($winnerPaths.ContainsKey($ancestor)) {
                $other = $winnerPaths[$ancestor]
                $message = "A file destination contains another file destination: '$($candidate.DestinationPath)' and '$($other.DestinationPath)'."
                & $addError DestinationOverlap @($candidate.Entry, $other.Entry) $message
            }
            $ancestor = [IO.Path]::GetDirectoryName($ancestor)
        }
    }
    # Classify existing destinations for both preview and execution. Conflicts are
    # data, not validation failures: linking applies the established prompt switches.
    foreach ($candidate in $winners) {
        $candidate.ExistingState = Get-HomepsickExistingLinkState `
            -Candidate $candidate -Mappings $mappings -RepositoryPath $RepositoryPath
        if ($manifest.HasManifest) {
            $obstacle = Get-HomepsickPathObstacle -Path $candidate.DestinationPath
            if ($obstacle) {
                $candidate.ExistingState = 'Blocked'
                $candidate.Reason = $obstacle
                & $addError UnsafeDestination $candidate.Entry $obstacle
            }
        }
        if (-not $candidate.Allowed) { $candidate.Reason = 'Requires -AllowOutsideHome before modifying this destination.' }
        elseif ($candidate.ExistingState -eq 'Conflict') {
            $existing = Get-Item -LiteralPath $candidate.DestinationPath -Force
            $candidate.Reason = if ($existing.PSIsContainer -and $existing.LinkType -ne 'SymbolicLink') {
                'Existing directory conflict remains for review; directory trees are never replaced.'
            } else { 'Existing destination conflicts with the proposed link.' }
        }
    }
    [HomepsickLinkPlan]@{
        RepositoryPath = $RepositoryPath; HasManifest = $manifest.HasManifest
        MachineFacts = $detected.Facts; FactNotes = $detected.Notes; Entries = $entries
        Candidates = @($candidates); Winners = $winners; RootMappings = @($mappings)
        Shadowed = @($candidates | Where-Object Status -eq Shadowed); Ties = @($candidates | Where-Object Status -eq Tie)
        Conflicts = @($winners | Where-Object { $_.ExistingState -in @('Conflict', 'Blocked') })
        Errors = @($errors); Warnings = @($warnings); IsValid = ($errors.Count -eq 0)
    }
}
