function Enable-HomepsickCastle {
    <#
    .SYNOPSIS
    Links Git-tracked castle files using the shared destination plan.
    .DESCRIPTION
    Selects applicable roots and links their winning files. Conflicts with other
    castles retain the ordinary confirmation, skip, and force behavior.
    .PARAMETER CastleName
    Name of one installed castle to link.
    .PARAMETER All
    Links every installed castle. This is the default when CastleName is omitted.
    .PARAMETER Force
    Replaces conflicting individual files or symbolic links without asking.
    Never replaces a directory tree. Skip takes precedence over Force.
    .PARAMETER Skip
    Leaves conflicting files and symbolic links untouched.
    .PARAMETER Batch
    Skips conflict prompts and leaves conflicts untouched unless Force is supplied.
    .PARAMETER AllowOutsideHome
    Authorizes writes to destinations explicitly declared with outsideHome: true.
    .PARAMETER MachineFacts
    A complete synthetic fact context for root selection; omitted facts are unavailable.
    .EXAMPLE
    Enable-HomepsickCastle -CastleName dotfiles -Batch -WhatIf
    Previews linking one castle while skipping existing conflicts.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Single')][string]$CastleName,
        [Parameter(ParameterSetName = 'All')][switch]$All,
        [switch]$Force,
        [switch]$Skip,
        [switch]$Batch,
        [switch]$AllowOutsideHome,
        [System.Collections.IDictionary]$MachineFacts
    )

    $names = if ($PSCmdlet.ParameterSetName -eq 'Single') { @($CastleName) } else { @(Get-HomepsickNames) }
    foreach ($name in $names) {
        $castle = Get-HomepsickCastle -CastleName $name
        $plan = Resolve-HomepsickLinkPlan -RepositoryPath $castle.CastlePath -MachineFacts $MachineFacts -AllowOutsideHome:$AllowOutsideHome
        if (-not $plan.IsValid) {
            throw "Castle '$name' has an invalid link plan: $((Format-HomepsickDiagnostic $plan.Errors) -join [Environment]::NewLine)"
        }
        foreach ($warning in @($plan.Warnings | Where-Object Code -ne PotentialTie)) {
            Write-Warning (Format-HomepsickDiagnostic @($warning))
        }

        foreach ($file in $plan.Winners) {
            if (-not $file.Allowed) {
                Write-Warning "Skipping '$($file.DestinationPath)': $($file.Reason)"
                continue
            }
            $link = $file.DestinationPath
            $parent = Split-Path -Parent $link
            $target = [IO.Path]::GetRelativePath($parent, $file.SourcePath)
            if ($plan.HasManifest) {
                # Recheck immediately before writing; the plan may have been produced
                # before a prompt, and parent links must never redirect these writes.
                $obstacle = Get-HomepsickPathObstacle -Path $link
                if ($obstacle) { throw $obstacle }
            }
            if (Test-HomepsickEntry -LiteralPath $link) {
                $existing = Get-Item -LiteralPath $link -Force
                $existingTarget = if ($existing.LinkType -eq 'SymbolicLink') { @($existing.Target)[0] } else { $null }
                $state = Get-HomepsickExistingLinkState -Candidate $file -Mappings $plan.RootMappings -RepositoryPath $castle.CastlePath
                $alreadyLinked = if ($plan.HasManifest) { $state -eq 'AlreadyLinked' } else {
                    $existingTarget -and [IO.Path]::GetFullPath([IO.Path]::Combine($parent, $existingTarget)) -eq $file.SourcePath
                }
                if ($alreadyLinked) {
                    Write-Verbose "Already linked: $link"
                    continue
                }
                # A directory may contain unrelated files; even Force must never
                # turn one file conflict into recursive deletion. Directory links
                # can be removed individually without touching their targets.
                if ($existing.PSIsContainer -and $existing.LinkType -ne 'SymbolicLink') {
                    Write-Warning "[DirectoryConflict] $($file.Entry): Leaving directory '$link' for review; directory trees are never replaced."
                    continue
                }
                # Current target + current mapping establish managed ownership,
                # including mappings inactive on this machine. No history is stored.
                $managed = $plan.HasManifest -and $state -eq 'ManagedLink'
                if ($managed) {
                    if (-not $PSCmdlet.ShouldProcess($link, 'Update managed castle link')) { continue }
                    if ((Get-HomepsickExistingLinkState -Candidate $file -Mappings $plan.RootMappings -RepositoryPath $castle.CastlePath) -ne 'ManagedLink') {
                        throw "Managed link changed during confirmation: '$link'."
                    }
                    Remove-Item -LiteralPath $link -Force -ErrorAction Stop
                }
                else {
                    # Skip wins over Force; Batch skips unless Force explicitly
                    # requests replacement. Cross-castle conflicts use this path.
                    if ($Skip -or ($Batch -and -not $Force)) {
                        Write-Verbose "Skipping existing path: $link"
                        continue
                    }
                    if (-not $Force -and -not $PSCmdlet.ShouldContinue("Replace existing path '$link'?", 'Castle link conflict')) {
                        continue
                    }
                    if (-not $PSCmdlet.ShouldProcess($link, 'Replace with castle link')) { continue }
                    # Confirmation can run user code: recheck parents and the
                    # current entry before removing the single destination.
                    if ($plan.HasManifest) {
                        $obstacle = Get-HomepsickPathObstacle -Path $link
                        if ($obstacle) { throw $obstacle }
                    }
                    $current = Get-Item -LiteralPath $link -Force -ErrorAction Stop
                    if ($current.PSIsContainer -and $current.LinkType -ne 'SymbolicLink') {
                        throw "[DirectoryConflict] $($file.Entry): Destination became a directory during confirmation: '$link'."
                    }
                    Remove-Item -LiteralPath $link -Force -ErrorAction Stop
                }
            }
            elseif (-not $PSCmdlet.ShouldProcess($link, 'Create castle link')) { continue }

            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
            New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
            Write-Verbose "Linked $link to $target"
        }
    }
}
