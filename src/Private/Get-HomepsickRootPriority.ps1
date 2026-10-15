function Get-HomepsickRootPriority {
    # Returns the additive integer score of explicitly declared condition fields.
    # Multiple alternatives broaden a match, so two or more values halve that
    # field's weight. A singleton array remains equivalent to a scalar.
    param([System.Collections.IDictionary]$When)
    $weights = @{ os = 100; distroLike = 1000; windowsRole = 1000; distro = 10000; distroVersion = 10000; windowsRelease = 10000; windowsEdition = 10000; host = 100000 }
    $score = 0
    foreach ($key in $When.Keys) {
        $score += if (@($When[$key]).Count -gt 1) { $weights[$key] / 2 } else { $weights[$key] }
    }
    return [int]$score
}
