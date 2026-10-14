function Enable-HomepsickCastle {
    <# .SYNOPSIS Links Git-tracked castle files using the shared destination plan. #>
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
        foreach ($warning in $plan.Warnings) { Write-Warning "$($warning.Entries -join ', '): $($warning.Message)" }
        if (-not $plan.IsValid) {
            throw "Castle '$name' has an invalid link plan: $($plan.Errors.Message -join ' ')"
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
                if ($plan.HasManifest -and $file.OutsideHome) {
                    if ($state -ne 'ManagedLink') {
                        Write-Warning "External destination conflict at '$link'; only a verified link from this castle can be replaced."
                        continue
                    }
                }
                $managed = $plan.HasManifest -and $state -eq 'ManagedLink'
                if ($managed) {
                    if (-not $PSCmdlet.ShouldProcess($link, 'Update managed castle link')) { continue }
                    if ((Get-HomepsickExistingLinkState -Candidate $file -Mappings $plan.RootMappings -RepositoryPath $castle.CastlePath) -ne 'ManagedLink') {
                        throw "Managed link changed during confirmation: '$link'."
                    }
                    Remove-Item -LiteralPath $link -Force -ErrorAction Stop
                }
                else {
                    if ($Skip -or ($Batch -and -not $Force)) {
                        Write-Verbose "Skipping existing path: $link"
                        continue
                    }
                    if (-not $Force -and -not $PSCmdlet.ShouldContinue("Replace existing path '$link'?", 'Castle link conflict')) {
                        continue
                    }
                    if (-not $PSCmdlet.ShouldProcess($link, 'Replace with castle link')) { continue }
                    Remove-Item -LiteralPath $link -Force -Recurse -ErrorAction Stop
                }
            }
            elseif (-not $PSCmdlet.ShouldProcess($link, 'Create castle link')) { continue }

            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
            New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
            Write-Verbose "Linked $link to $target"
        }
    }
}
