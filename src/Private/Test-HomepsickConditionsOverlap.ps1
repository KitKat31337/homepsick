function Test-HomepsickConditionsOverlap {
    # Returns whether two entries could select together, conservatively for static warnings.
    # Different distroLike alternatives can coexist in one ID_LIKE list, unlike
    # mutually exclusive exact IDs, releases, editions, or host names.
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
