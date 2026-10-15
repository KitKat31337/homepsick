function Get-HomepsickRootSelection {
    # Returns a HomepsickRootSelection for every root, with selection and skip reasons.
    # Fields combine with AND, alternatives within a field with OR. Linux and
    # Windows facts only apply on their own OS even without an explicit os field.
    [OutputType([HomepsickRootSelection])]
    param([HomepsickManifestRoot[]]$Roots, [HomepsickMachineFacts]$Facts)
    foreach ($root in $Roots) {
        $reasons = [Collections.Generic.List[string]]::new()
        # Keep inferred destination requirements out of When so they cannot change
        # scoring. Missing foreign drives/directories are irrelevant to skipped roots.
        if ($root.DestinationOS.Count -and $Facts.os -notin $root.DestinationOS) {
            $reasons.Add("Destination '$($root.Target)' requires OS '$($root.DestinationOS -join ', ')'; detected OS is '$($Facts.os)'.")
        }
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
        [HomepsickRootSelection]@{
            Entry = $root.Entry; Source = $root.Source; Target = $root.Target; Into = $root.Into
            When = $root.When; Priority = $root.Priority; CalculatedPriority = $root.CalculatedPriority
            DestinationOS = $root.DestinationOS
            PriorityOverridden = $root.PriorityOverridden; Implicit = $root.Implicit
            Selected = ($reasons.Count -eq 0)
            Reasons = if ($reasons.Count) { @($reasons) } else { @('All conditions match.') }
        }
    }
}
