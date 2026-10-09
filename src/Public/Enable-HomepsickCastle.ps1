function Enable-HomepsickCastle {
    <# .SYNOPSIS Links Git-tracked castle files into the home directory. #>
    [CmdletBinding(DefaultParameterSetName = 'All', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Single')][string]$CastleName,
        [Parameter(ParameterSetName = 'All')][switch]$All,
        [switch]$Force,
        [switch]$Skip,
        [switch]$Batch
    )

    $names = if ($PSCmdlet.ParameterSetName -eq 'Single') { @($CastleName) } else { @(Get-HomepsickNames) }
    $homePath = Get-HomePath
    foreach ($name in $names) {
        $castle = Get-HomepsickCastle -CastleName $name
        if (-not (Test-Path -LiteralPath $castle.CastleSymRoot -PathType Container)) {
            Write-Verbose "Castle '$name' has no home directory."
            continue
        }

        foreach ($file in @(Get-HomepsickTrackedFile -RepositoryPath $castle.CastlePath)) {
            $link = Join-Path $homePath $file.RelativePath
            $parent = Split-Path -Parent $link
            $target = [IO.Path]::GetRelativePath($parent, $file.SourcePath)
            if (Test-HomepsickEntry -LiteralPath $link) {
                $existing = Get-Item -LiteralPath $link -Force
                $existingTarget = if ($existing.LinkType -eq 'SymbolicLink') { @($existing.Target)[0] } else { $null }
                if ($existingTarget -and
                    [IO.Path]::GetFullPath([IO.Path]::Combine($parent, $existingTarget)) -eq $file.SourcePath) {
                    Write-Verbose "Already linked: $link"
                    continue
                }
                if ($Skip -or ($Batch -and -not $Force)) {
                    Write-Verbose "Skipping existing path: $link"
                    continue
                }
                if (-not $Force -and -not $PSCmdlet.ShouldContinue("Replace existing path '$link'?", 'Castle link conflict')) {
                    continue
                }
                if (-not $PSCmdlet.ShouldProcess($link, 'Replace with castle link')) { continue }
                Remove-Item -LiteralPath $link -Force -Recurse
            }
            elseif (-not $PSCmdlet.ShouldProcess($link, 'Create castle link')) { continue }

            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
            Write-Verbose "Linked $link to $target"
        }
    }
}
