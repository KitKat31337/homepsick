function Get-HomepsickRootPriority {
    param([System.Collections.IDictionary]$When)
    $weights = @{ os = 100; distroLike = 1000; windowsRole = 1000; distro = 10000; distroVersion = 10000; windowsRelease = 10000; windowsEdition = 10000; host = 100000 }
    $score = 0
    foreach ($key in $When.Keys) {
        $score += if (@($When[$key]).Count -gt 1) { $weights[$key] / 2 } else { $weights[$key] }
    }
    return [int]$score
}

function Get-HomepsickConditionOS {
    param([System.Collections.IDictionary]$When)
    $systems = @('windows', 'linux', 'macos', 'freebsd')
    if ($When.Contains('os')) { $systems = @($When.os) }
    if (@($When.Keys | Where-Object { $_ -in @('distro', 'distroLike', 'distroVersion') }).Count) {
        $systems = @($systems | Where-Object { $_ -eq 'linux' })
    }
    if (@($When.Keys | Where-Object { $_ -in @('windowsRole', 'windowsRelease', 'windowsEdition') }).Count) {
        $systems = @($systems | Where-Object { $_ -eq 'windows' })
    }
    return $systems
}

function Test-HomepsickConditionsOverlap {
    param([System.Collections.IDictionary]$Left, [System.Collections.IDictionary]$Right)
    $rightOS = @(Get-HomepsickConditionOS $Right)
    if (-not @(Get-HomepsickConditionOS $Left | Where-Object { $_ -in $rightOS }).Count) { return $false }
    foreach ($key in $Left.Keys) {
        # ID_LIKE can contain multiple lineages simultaneously.
        if ($key -ne 'distroLike' -and $Right.Contains($key) -and
            -not @($Left[$key] | Where-Object { $_ -in @($Right[$key]) }).Count) { return $false }
    }
    return $true
}

function Get-HomepsickRootSelection {
    param([object[]]$Roots, [object]$Facts)
    foreach ($root in $Roots) {
        $reasons = [Collections.Generic.List[string]]::new()
        foreach ($key in $root.When.Keys) {
            $platform = if ($key -in @('distro', 'distroLike', 'distroVersion')) { 'linux' }
                elseif ($key -in @('windowsRole', 'windowsRelease', 'windowsEdition')) { 'windows' }
            if ($platform -and $Facts.os -ne $platform) {
                $reasons.Add("$key requires $platform; detected OS is '$($Facts.os)'.")
                continue
            }
            $actual = @($Facts.$key | Where-Object { -not [string]::IsNullOrEmpty($_) })
            if (-not $actual.Count) { $reasons.Add("Machine fact '$key' is unavailable."); continue }
            if (-not @($actual | Where-Object { $_ -in @($root.When[$key]) }).Count) {
                $reasons.Add("$key '$($actual -join ', ')' does not match '$($root.When[$key] -join ', ')'.")
            }
        }
        [pscustomobject]@{
            Entry = $root.Entry; Source = $root.Source; Target = $root.Target; Into = $root.Into
            When = $root.When; Priority = $root.Priority; CalculatedPriority = $root.CalculatedPriority
            PriorityOverridden = $root.PriorityOverridden; Implicit = $root.Implicit
            Selected = ($reasons.Count -eq 0)
            Reasons = if ($reasons.Count) { @($reasons) } else { @('All conditions match.') }
        }
    }
}
