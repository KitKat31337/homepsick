function Test-HomepsickConditionsOverlap {
    # Returns whether two entries could select together, conservatively for static warnings.
    # Different distroLike alternatives can coexist in one ID_LIKE list, unlike
    # mutually exclusive exact IDs, releases, editions, or host names.
    param([HomepsickManifestRoot]$Left, [HomepsickManifestRoot]$Right)
    $leftOS = @(Get-HomepsickConditionOS -When $Left.When -DestinationOS $Left.DestinationOS)
    $rightOS = @(Get-HomepsickConditionOS -When $Right.When -DestinationOS $Right.DestinationOS)
    if (-not @($leftOS | Where-Object { $_ -in $rightOS }).Count) { return $false }
    foreach ($key in $Left.When.Keys) {
        # ID_LIKE can contain multiple lineages simultaneously.
        if ($key -ne 'distroLike' -and $Right.When.Contains($key) -and
            -not @($Left.When[$key] | Where-Object { $_ -in @($Right.When[$key]) }).Count) { return $false }
    }
    return $true
}
