function Get-HomepsickConditionOS {
    # Returns OS families compatible with conditions and destination syntax, or
    # nothing if unreachable. Inferred platform requirements never add priority.
    param([System.Collections.IDictionary]$When, [string[]]$DestinationOS = @())
    $systems = @('windows', 'linux', 'macos', 'freebsd')
    if ($When.Contains('os')) { $systems = @($When.os) }
    if (@($When.Keys | Where-Object { $_ -in @('distro', 'distroLike', 'distroVersion') }).Count) {
        $systems = @($systems | Where-Object { $_ -eq 'linux' })
    }
    if (@($When.Keys | Where-Object { $_ -in @('windowsRole', 'windowsRelease', 'windowsEdition') }).Count) {
        $systems = @($systems | Where-Object { $_ -eq 'windows' })
    }
    if ($DestinationOS.Count) { $systems = @($systems | Where-Object { $_ -in $DestinationOS }) }
    return $systems
}
