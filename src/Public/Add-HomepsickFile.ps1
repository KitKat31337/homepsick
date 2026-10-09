function Add-HomepsickFile {
    <# .SYNOPSIS Moves home files into a castle, links them back, and stages them in Git. #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$CastleName,
        [Parameter(Mandatory, ValueFromPipeline)][string[]]$Path
    )

    begin {
        $castle = Get-HomepsickCastle -CastleName $CastleName
        if (-not (Test-Path -LiteralPath $castle.CastleSymRoot -PathType Container)) {
            throw "Castle '$CastleName' has no home directory."
        }
        $home = [IO.Path]::GetFullPath((Get-HomePath))
    }
    process {
        foreach ($inputPath in $Path) {
            $absolute = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($inputPath))
            $relative = [IO.Path]::GetRelativePath($home, $absolute)
            if ($relative -eq '.' -or $relative -eq '..' -or
                $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -or
                [IO.Path]::IsPathRooted($relative)) {
                throw "'$inputPath' must be inside the home directory."
            }
            if (-not (Test-HomepsickEntry -LiteralPath $absolute)) { throw "'$inputPath' does not exist." }
            $item = Get-Item -LiteralPath $absolute -Force
            $files = if ($item.PSIsContainer -and -not $item.LinkType) {
                @(Get-ChildItem -LiteralPath $absolute -Recurse -Force |
                    Where-Object { (-not $_.PSIsContainer -or $_.LinkType -eq 'SymbolicLink') -and
                        $_.FullName -notmatch '[\\/][.]git[\\/]' })
            } else { @($item) }

            foreach ($file in $files) {
                $fileRelative = [IO.Path]::GetRelativePath($home, $file.FullName)
                $destination = Join-Path $castle.CastleSymRoot $fileRelative
                if (Test-HomepsickEntry -LiteralPath $destination) {
                    Write-Verbose "Already tracked: $fileRelative"
                    continue
                }
                $repoRelative = ('home/' + $fileRelative.Replace('\', '/'))
                $ignored = Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('check-ignore', '--quiet', '--', $repoRelative) -AllowFailure
                if ($ignored.ExitCode -notin @(0, 1)) { throw "Unable to check Git ignore rules for '$repoRelative': $($ignored.Error)" }
                if ($ignored.ExitCode -eq 0) {
                    Write-Warning "Git ignores '$repoRelative'; skipping."
                    continue
                }
                if (-not $PSCmdlet.ShouldProcess($file.FullName, "Move into castle '$CastleName' and link back")) { continue }
                $parent = Split-Path -Parent $destination
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
                $relativeTarget = [IO.Path]::GetRelativePath((Split-Path -Parent $file.FullName), $destination)
                try {
                    if ($file.LinkType -eq 'SymbolicLink' -and
                        -not [IO.Path]::IsPathRooted(@($file.Target)[0])) {
                        $originalTarget = [IO.Path]::GetFullPath([IO.Path]::Combine((Split-Path -Parent $file.FullName), @($file.Target)[0]))
                        $newTarget = [IO.Path]::GetRelativePath($parent, $originalTarget)
                        New-Item -ItemType SymbolicLink -Path $destination -Target $newTarget | Out-Null
                        Remove-Item -LiteralPath $file.FullName -Force
                    }
                    else { Move-Item -LiteralPath $file.FullName -Destination $destination }
                    New-Item -ItemType SymbolicLink -Path $file.FullName -Target $relativeTarget | Out-Null
                    Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('add', '--', $repoRelative) | Out-Null
                    Write-Verbose "Tracked $fileRelative"
                }
                catch {
                    # Restore the original file if linking or staging fails.
                    if (Test-HomepsickEntry -LiteralPath $file.FullName) {
                        Remove-Item -LiteralPath $file.FullName -Force
                    }
                    if (Test-HomepsickEntry -LiteralPath $destination) {
                        if ($file.LinkType -eq 'SymbolicLink' -and $originalTarget -and
                            -not [IO.Path]::IsPathRooted(@($file.Target)[0])) {
                            Remove-Item -LiteralPath $destination -Force
                            New-Item -ItemType SymbolicLink -Path $file.FullName -Target @($file.Target)[0] | Out-Null
                        }
                        else { Move-Item -LiteralPath $destination -Destination $file.FullName }
                    }
                    throw
                }
            }
        }
    }
}
