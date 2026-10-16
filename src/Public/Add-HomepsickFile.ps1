function Add-HomepsickFile {
    <#
    .SYNOPSIS
    Moves destination files into an applicable castle root, stages them, and links them back.
    .PARAMETER CastleName
    Name of the installed castle that receives the files.
    .PARAMETER Path
    Files or directories beneath an applicable destination. Accepts pipeline input.
    .PARAMETER Root
    Source directory or roots[n] identifier to select when multiple mappings qualify.
    .PARAMETER AllowOutsideHome
    Authorizes tracking from explicitly declared destinations outside home.
    .PARAMETER MachineFacts
    A complete synthetic fact context for manifest root selection; omitted facts are unavailable.
    .EXAMPLE
    Add-HomepsickFile -CastleName dotfiles -Path "$HOME/.config/editor/settings.json" -Root editor_settings -WhatIf
    Previews tracking editor settings into the selected manifest source root.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$CastleName,
        [Parameter(Mandatory, ValueFromPipeline)][string[]]$Path,
        [string]$Root,
        [switch]$AllowOutsideHome,
        [System.Collections.IDictionary]$MachineFacts
    )

    begin {
        $castle = Get-HomepsickCastle -CastleName $CastleName
        $hasManifest = Test-HomepsickEntry (Join-Path $castle.CastlePath 'homepsick.json')
        if (-not $hasManifest -and -not (Test-Path -LiteralPath $castle.CastleSymRoot -PathType Container)) {
            throw "Castle '$CastleName' has no home directory."
        }
        if (-not $hasManifest -and $Root -and $Root -notin @('home', 'implicit home')) {
            throw "[NoTrackingRoot] A castle without a manifest tracks files into home/."
        }
        $homePath = [IO.Path]::GetFullPath((Get-HomePath))
    }
    process {
        foreach ($inputPath in $Path) {
            $plan = if ($hasManifest) {
                Resolve-HomepsickLinkPlan -RepositoryPath $castle.CastlePath -MachineFacts $MachineFacts -AllowOutsideHome:$AllowOutsideHome
            }
            if ($hasManifest -and -not $plan.IsValid) {
                throw "Castle '$CastleName' has an invalid tracking plan: $((Format-HomepsickDiagnostic $plan.Errors) -join [Environment]::NewLine)"
            }
            $absolute = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($inputPath))
            $relative = [IO.Path]::GetRelativePath($homePath, $absolute)
            if (-not $hasManifest -and ($relative -eq '.' -or $relative -eq '..' -or
                $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
                [IO.Path]::IsPathRooted($relative))) {
                throw "'$inputPath' must be inside the home directory."
            }
            if (-not (Test-HomepsickEntry -LiteralPath $absolute)) { throw "'$inputPath' does not exist." }
            $item = Get-Item -LiteralPath $absolute -Force
            if ($hasManifest -and $item.PSIsContainer -and -not $item.LinkType) {
                $obstacle = Get-HomepsickPathObstacle -Path $absolute -IncludeLeaf
                if ($obstacle) { throw "[UnsafeTrackingPath] $obstacle" }
            }
            $files = if ($item.PSIsContainer -and -not $item.LinkType) {
                @(Get-ChildItem -LiteralPath $absolute -Recurse -Force -ErrorAction Stop |
                    Where-Object { (-not $_.PSIsContainer -or $_.LinkType -eq 'SymbolicLink') -and
                        $_.FullName -notmatch '[\\/][.]git[\\/]' })
            } else { @($item) }

            # Validate every file in this input before moving any of them, so a
            # later ambiguous mapping or unsafe path does not partially track a directory.
            $tracking = foreach ($file in $files) {
                $mapping = if ($hasManifest) {
                    Resolve-HomepsickTrackingPath -Plan $plan -Path $file.FullName -Root $Root -AllowOutsideHome:$AllowOutsideHome
                } else {
                    $fileRelative = [IO.Path]::GetRelativePath($homePath, $file.FullName)
                    [HomepsickTrackingPath]@{
                        SourcePath = (Join-Path $castle.CastleSymRoot $fileRelative)
                        RelativePath = $fileRelative; RepositoryRelativePath = ('home/' + $fileRelative.Replace('\', '/'))
                    }
                }
                [pscustomobject]@{ File = $file; Mapping = $mapping }
            }
            foreach ($operation in $tracking) {
                $file = $operation.File
                $originalLinkTarget = if ($file.LinkType -eq 'SymbolicLink') { @($file.Target)[0] } else { $null }
                $fileRelative = $operation.Mapping.RelativePath
                $destination = $operation.Mapping.SourcePath
                if (Test-HomepsickEntry -LiteralPath $destination) {
                    Write-Verbose "Already tracked: $fileRelative"
                    continue
                }
                $repoRelative = $operation.Mapping.RepositoryRelativePath
                $gitRepository = $castle.CastlePath
                $gitRelative = $repoRelative
                if ($hasManifest) {
                    # Initialized submodules own their file indexes. Stage there so
                    # the castle's existing recursive enumeration sees the new file.
                    $existingParent = Split-Path -Parent $destination
                    while (-not (Test-Path -LiteralPath $existingParent -PathType Container)) {
                        $existingParent = Split-Path -Parent $existingParent
                    }
                    $gitRepository = [IO.Path]::GetFullPath((Invoke-HomepsickGit -RepositoryPath $existingParent -Arguments @('rev-parse', '--show-toplevel')).Output.Trim())
                    if (-not (Test-HomepsickContainedPath -Parent $castle.CastlePath -Path $gitRepository -AllowEqual)) {
                        throw "[UnsafeTrackingPath] $($operation.Mapping.Entry): The source index is outside this castle."
                    }
                    $gitRelative = [IO.Path]::GetRelativePath($gitRepository, $destination).Replace('\', '/')
                }
                $ignored = Invoke-HomepsickGit -RepositoryPath $gitRepository -Arguments @('check-ignore', '--quiet', '--', $gitRelative) -AllowFailure
                if ($ignored.ExitCode -notin @(0, 1)) { throw "Unable to check Git ignore rules for '$repoRelative': $($ignored.Error)" }
                if ($ignored.ExitCode -eq 0) {
                    Write-Warning "Git ignores '$repoRelative'; skipping."
                    continue
                }
                $action = if ($hasManifest) {
                    "$($operation.Mapping.Entry): Move into '$destination', stage in Git, and link back through the castle plan"
                } else { "Move into castle '$CastleName' and link back" }
                if (-not $PSCmdlet.ShouldProcess($file.FullName, $action)) { continue }
                $parent = Split-Path -Parent $destination
                if ($hasManifest) {
                    foreach ($pathToCheck in @($file.FullName, $destination)) {
                        $obstacle = Get-HomepsickPathObstacle -Path $pathToCheck
                        if ($obstacle) { throw "[UnsafeTrackingPath] $($operation.Mapping.Entry): $obstacle" }
                    }
                }
                # Snapshot only this path's stages; rollback must preserve both
                # its preexisting index content and all unrelated staged work.
                $indexBefore = (Invoke-HomepsickGit -RepositoryPath $gitRepository -Arguments @('ls-files', '--stage', '-z', '--', $gitRelative)).Output
                New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
                $relativeTarget = [IO.Path]::GetRelativePath((Split-Path -Parent $file.FullName), $destination)
                $originalTarget = $null
                $castleFileCreated = $false
                $originalRemoved = $false
                $linkCreated = $false
                $stagingAttempted = $false
                try {
                    # Moving a relative symlink changes its meaning. Rebase its
                    # target at the castle location, retaining the original text
                    # so rollback can restore the exact destination-side link.
                    if ($originalLinkTarget -and -not [IO.Path]::IsPathRooted($originalLinkTarget)) {
                        $originalTarget = [IO.Path]::GetFullPath([IO.Path]::Combine((Split-Path -Parent $file.FullName), $originalLinkTarget))
                        $newTarget = [IO.Path]::GetRelativePath($parent, $originalTarget)
                        New-Item -ItemType SymbolicLink -Path $destination -Target $newTarget -ErrorAction Stop | Out-Null
                        $castleFileCreated = $true
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                        $originalRemoved = $true
                    }
                    else {
                        Move-Item -LiteralPath $file.FullName -Destination $destination -ErrorAction Stop
                        $castleFileCreated = $true
                        $originalRemoved = $true
                    }
                    if ($hasManifest) {
                        $stagingAttempted = $true
                        Invoke-HomepsickGit -RepositoryPath $gitRepository -Arguments @('add', '--', $gitRelative) | Out-Null
                        # Only staged files are candidates. Rebuild after staging
                        # and link the actual winner, which may be another root
                        # than the one explicitly chosen for storing this new file.
                        $updatedPlan = Resolve-HomepsickLinkPlan -RepositoryPath $castle.CastlePath -MachineFacts $MachineFacts -AllowOutsideHome:$AllowOutsideHome
                        if (-not $updatedPlan.IsValid) {
                            throw "Invalid tracking link plan: $((Format-HomepsickDiagnostic $updatedPlan.Errors) -join [Environment]::NewLine)"
                        }
                        $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
                        $winner = @($updatedPlan.Winners | Where-Object { [string]::Equals($_.DestinationPath, $file.FullName, $comparison) })
                        if ($winner.Count -ne 1) { throw "[NoTrackingWinner] $($operation.Mapping.Entry): No winning file maps back to '$($file.FullName)'." }
                        $relativeTarget = [IO.Path]::GetRelativePath((Split-Path -Parent $file.FullName), $winner[0].SourcePath)
                    }
                    New-Item -ItemType SymbolicLink -Path $file.FullName -Target $relativeTarget -ErrorAction Stop | Out-Null
                    $linkCreated = $true
                    if (-not $hasManifest) {
                        $stagingAttempted = $true
                        Invoke-HomepsickGit -RepositoryPath $gitRepository -Arguments @('add', '--', $gitRelative) | Out-Null
                    }
                    Write-Verbose "Tracked $fileRelative"
                }
                catch {
                    # Restore just this operation's file and index entry. Other staged
                    # work must survive a failure, including preexisting index content.
                    if ($linkCreated -and (Test-HomepsickEntry -LiteralPath $file.FullName)) {
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    }
                    if ($castleFileCreated) {
                        if ($originalTarget) {
                            Remove-Item -LiteralPath $destination -Force -ErrorAction Stop
                            if ($originalRemoved) {
                                New-Item -ItemType SymbolicLink -Path $file.FullName -Target $originalLinkTarget -ErrorAction Stop | Out-Null
                            }
                        }
                        elseif ($originalRemoved) { Move-Item -LiteralPath $destination -Destination $file.FullName -ErrorAction Stop }
                    }
                    if ($stagingAttempted) {
                        $indexAfter = (Invoke-HomepsickGit -RepositoryPath $gitRepository -Arguments @('ls-files', '--stage', '-z', '--', $gitRelative)).Output
                        if ($indexAfter -cne $indexBefore) {
                            Invoke-HomepsickGit -RepositoryPath $gitRepository -Arguments @('update-index', '--force-remove', '--', $gitRelative) | Out-Null
                            if ($indexBefore) {
                                Invoke-HomepsickGit -RepositoryPath $gitRepository -Arguments @('update-index', '-z', '--index-info') -InputText $indexBefore | Out-Null
                            }
                        }
                    }
                    throw
                }
            }
        }
    }
}
