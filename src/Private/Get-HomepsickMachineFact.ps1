function Get-HomepsickMachineFact {
    [CmdletBinding()]
    param(
        [System.Collections.IDictionary]$Context,
        [System.Collections.IDictionary]$MachineFacts
    )

    $facts = [ordered]@{
        os = $null; host = $null; distro = $null; distroLike = @(); distroVersion = $null
        windowsRole = $null; windowsRelease = $null; windowsEdition = $null
    }
    $notes = [Collections.Generic.List[string]]::new()
    if ($null -ne $MachineFacts) {
        foreach ($key in $MachineFacts.Keys) {
            if ($key -notin @($facts.Keys)) { throw "Unknown machine fact '$key'." }
            if ($key -eq 'distroLike') {
                $facts[$key] = @($MachineFacts[$key] | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
            }
            elseif ($null -ne $MachineFacts[$key]) {
                $facts[$key] = ([string]$MachineFacts[$key]).Trim().ToLowerInvariant()
            }
        }
    }
    else {
        if ($null -eq $Context) {
            $Context = @{ host = [Environment]::MachineName }
            $Context.os = if ($IsWindows) { 'windows' } elseif ($IsLinux) { 'linux' } elseif ($IsMacOS) { 'macos' } else { 'freebsd' }
            if ($IsWindows) {
                try {
                    $system = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                    $Context.windows = @{
                        ProductType = $system.ProductType; BuildNumber = $system.BuildNumber
                        Caption = $system.Caption; OperatingSystemSKU = $system.OperatingSystemSKU
                    }
                }
                catch { $notes.Add("Windows product information unavailable: $($_.Exception.Message)") }
            }
            elseif ($IsLinux) {
                $releasePath = if (Test-Path -LiteralPath '/etc/os-release') { '/etc/os-release' } else { '/usr/lib/os-release' }
                try { $Context.osRelease = Get-Content -LiteralPath $releasePath -Raw -ErrorAction Stop }
                catch { $notes.Add("Linux distribution information unavailable: $($_.Exception.Message)") }
            }
        }
        $facts.os = ([string]$Context.os).Trim().ToLowerInvariant()
        $facts.host = ([string]$Context.host).Trim().ToLowerInvariant()
        if ($facts.os -eq 'linux') {
            # Read os-release as data; never source it or evaluate shell substitutions.
            $release = @{}
            foreach ($line in (([string]$Context.osRelease) -split '\r?\n')) {
                if ($line -match '^(ID|ID_LIKE|VERSION_ID)=(.*)$') {
                    $key = $Matches[1]
                    $value = $Matches[2].Trim()
                    if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") { $value = $Matches[1] }
                    $release[$key] = $value.ToLowerInvariant()
                }
            }
            $facts.distro = $release.ID
            $facts.distroVersion = $release.VERSION_ID
            $facts.distroLike = @(([string]$release.ID_LIKE -split '\s+') | Where-Object { $_ })
        }
        elseif ($facts.os -eq 'windows' -and $Context.windows) {
            $system = $Context.windows
            $facts.windowsRole = switch ([int]$system.ProductType) { 1 { 'workstation' } 2 { 'server' } 3 { 'server' } }
            $build = 0
            [void][int]::TryParse([string]$system.BuildNumber, [ref]$build)
            $caption = [string]$system.Caption
            if ($facts.windowsRole -eq 'server') {
                # Exact build families avoid misidentifying an unknown future Server release.
                $serverBuilds = @{ 14393 = 'server-2016'; 17763 = 'server-2019'; 20348 = 'server-2022'; 26100 = 'server-2025' }
                if ($serverBuilds.ContainsKey($build)) { $facts.windowsRelease = $serverBuilds[$build] }
            }
            elseif ($facts.windowsRole -eq 'workstation') {
                $windows10Builds = @(10240, 10586, 14393, 15063, 16299, 17134, 17763, 18362, 18363, 19041, 19042, 19043, 19044, 19045)
                $windows11Builds = @(22000, 22621, 22631, 26100, 26200, 28000)
                # Some Windows 11 registry/product strings still say Windows 10. Use build
                # families as well as product information, never just NT's major version.
                if ($caption -match '\bWindows 11\b' -and $build -ge 22000) { $facts.windowsRelease = '11' }
                elseif ($caption -notmatch '\bWindows (?:1[2-9]|[2-9][0-9])\b') {
                    if ($build -in $windows11Builds) { $facts.windowsRelease = '11' }
                    elseif ($build -in $windows10Builds) { $facts.windowsRelease = '10' }
                }
            }
            # SKU values are language independent. Normalize N, Core, evaluation,
            # workstation, and subscription variants to their edition families.
            # Values: Windows SDK winnt.h PRODUCT_* constants.
            $sku = [long]$system.OperatingSystemSKU
            $facts.windowsEdition = switch ($sku) {
                { $_ -in @(2, 3, 5, 26, 97, 98, 99, 100, 101, 111, 113, 115, 116) } { 'home'; break }
                { $_ -in @(48, 49, 103, 112, 114, 127, 128, 138, 139, 161, 162, 164, 165) } { 'pro'; break }
                { $_ -in @(4, 27, 70, 72, 84, 125, 126, 129, 130, 140, 141, 171, 172, 175, 188, 191, 205, 206, 207) } { 'enterprise'; break }
                { $_ -in @(121, 122) } { 'education'; break }
                { $_ -in @(7, 13, 36, 40, 79, 144, 146, 148, 160) } { 'standard'; break }
                { $_ -in @(8, 12, 37, 39, 80, 143, 145, 147, 159, 407, 408, 409) } { 'datacenter'; break }
            }
        }
    }
    # Injected facts obey the same platform boundaries as detected facts.
    if ($facts.os -ne 'linux') {
        $facts.distro = $null; $facts.distroVersion = $null; $facts.distroLike = @()
    }
    if ($facts.os -ne 'windows') {
        $facts.windowsRole = $null; $facts.windowsRelease = $null; $facts.windowsEdition = $null
    }
    foreach ($key in @('os', 'host', 'distro', 'distroVersion', 'windowsRole', 'windowsRelease', 'windowsEdition')) {
        if ([string]::IsNullOrEmpty($facts[$key])) { $facts[$key] = $null }
    }
    [pscustomobject]@{ Facts = [pscustomobject]$facts; Notes = @($notes) }
}
