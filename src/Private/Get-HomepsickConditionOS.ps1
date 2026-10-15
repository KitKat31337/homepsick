function Get-HomepsickConditionOS {
    # Returns the OS families compatible with all conditions, or nothing if unreachable.
    # Platform-specific fields imply an OS for matching, never extra priority.
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
