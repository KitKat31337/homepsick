# Tests raw platform normalization and every scoring tier using injected facts.
# Both Windows and Linux cases run on each CI host; no marketing identity is inferred
# from the host running the suite.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psd1') -Force
}

Describe 'Injectable machine fact detection' {
    It 'reads Linux IDs, release strings, and every ID_LIKE lineage as data' {
        $facts = & (Get-Module Homepsick) {
            (Get-HomepsickMachineFact -Context @{
                os = 'LINUX'; host = 'Machine1'
                osRelease = "ID=ubuntu`nVERSION_ID=`"24.04`"`nID_LIKE='debian linux'`nPRETTY_NAME=`"ignored`""
            }).Facts
        }
        $facts.os | Should -Be 'linux'
        $facts.host | Should -Be 'machine1'
        $facts.distro | Should -Be 'ubuntu'
        $facts.distroVersion | Should -Be '24.04'
        $facts.distroLike | Should -Be @('debian', 'linux')
        $facts.windowsRelease | Should -BeNullOrEmpty
    }

    It 'never executes os-release substitutions' {
        $facts = & (Get-Module Homepsick) {
            (Get-HomepsickMachineFact -Context @{ os = 'linux'; osRelease = 'ID="$(throw dangerous)"' }).Facts
        }
        $facts.distro | Should -Be '$(throw dangerous)'
    }

    It 'preserves exact distribution IDs and releases for <Distro>' -ForEach @(
        @{ Distro = 'fedora'; Version = '44'; Lineages = @() }
        @{ Distro = 'rocky'; Version = '9.6'; Lineages = @('rhel', 'centos', 'fedora') }
        @{ Distro = 'ubuntu'; Version = '24.04'; Lineages = @('debian') }
    ) {
        $context = @{ os = 'linux'; osRelease = "ID=$Distro`nVERSION_ID=`"$Version`"`nID_LIKE=`"$($Lineages -join ' ')`"" }
        $facts = & (Get-Module Homepsick) { param($Context) (Get-HomepsickMachineFact -Context $Context).Facts } $context
        $facts.distro | Should -Be $Distro
        $facts.distroVersion | Should -Be $Version
        @($facts.distroLike).Count | Should -Be $Lineages.Count
        if ($Lineages.Count) { $facts.distroLike | Should -Be $Lineages }
    }

    # Inject CIM data on both hosts: build+product type disambiguate the shared
    # server/workstation families, and localized or stale captions have no authority.
    It 'detects <Label> from numeric product type, build, and SKU' -ForEach @(
        @{ Label = 'Windows 10 Pro'; ProductType = 1; Caption = 'Microsoft Windows 10 Pro'; Build = 19045; SKU = 48; Role = 'workstation'; Release = '10'; Edition = 'pro' }
        @{ Label = 'Windows 11 with stale Windows 10 product text'; ProductType = 1; Caption = 'Windows 10 Pro'; Build = 22631; SKU = 48; Role = 'workstation'; Release = '11'; Edition = 'pro' }
        @{ Label = 'Windows 11 Home'; ProductType = 1; Caption = 'Windows 11 Home'; Build = 22000; SKU = 101; Role = 'workstation'; Release = '11'; Edition = 'home' }
        @{ Label = 'Windows 11 Enterprise N'; ProductType = 1; Caption = 'Windows 11 Enterprise N'; Build = 26100; SKU = 27; Role = 'workstation'; Release = '11'; Edition = 'enterprise' }
        @{ Label = 'Windows 11 Education'; ProductType = 1; Caption = 'Windows 11 Education'; Build = 26200; SKU = 121; Role = 'workstation'; Release = '11'; Edition = 'education' }
        @{ Label = 'Windows 11 with localized French caption'; ProductType = 1; Caption = 'Microsoft Windows 11 Professionnel'; Build = 22631; SKU = 48; Role = 'workstation'; Release = '11'; Edition = 'pro' }
        @{ Label = 'Windows 11 with non-English product text'; ProductType = 1; Caption = 'ウィンドウズ 11'; Build = 26100; SKU = 48; Role = 'workstation'; Release = '11'; Edition = 'pro' }
        @{ Label = 'Windows 10 without caption'; ProductType = 1; Caption = $null; Build = 19045; SKU = 48; Role = 'workstation'; Release = '10'; Edition = 'pro' }
        @{ Label = 'known Windows 11 build with misleading caption'; ProductType = 1; Caption = 'Windows 12 Pro'; Build = 22631; SKU = 48; Role = 'workstation'; Release = '11'; Edition = 'pro' }
        @{ Label = 'Server 2016 Standard'; ProductType = 3; Caption = 'Windows Server 2016 Standard'; Build = 14393; SKU = 7; Role = 'server'; Release = 'server-2016'; Edition = 'standard' }
        @{ Label = 'Server 2019 domain controller'; ProductType = 2; Caption = 'Windows Server 2019 Datacenter'; Build = 17763; SKU = 8; Role = 'server'; Release = 'server-2019'; Edition = 'datacenter' }
        @{ Label = 'Server 2022 Datacenter Core'; ProductType = 3; Caption = 'Windows Server 2022'; Build = 20348; SKU = 12; Role = 'server'; Release = 'server-2022'; Edition = 'datacenter' }
        @{ Label = 'Server 2025 Standard Evaluation'; ProductType = 3; Caption = 'Windows Server 2025'; Build = 26100; SKU = 79; Role = 'server'; Release = 'server-2025'; Edition = 'standard' }
        @{ Label = 'Server Standard Core WS'; ProductType = 3; Caption = 'Windows Server 2022'; Build = 20348; SKU = 148; Role = 'server'; Release = 'server-2022'; Edition = 'standard' }
        @{ Label = 'Server Datacenter Core Evaluation'; ProductType = 3; Caption = 'Windows Server 2022'; Build = 20348; SKU = 159; Role = 'server'; Release = 'server-2022'; Edition = 'datacenter' }
        @{ Label = 'unlicensed SKU'; ProductType = 1; Caption = 'Windows 11'; Build = 22631; SKU = 2882382797; Role = 'workstation'; Release = '11'; Edition = $null }
        @{ Label = 'unknown future workstation'; ProductType = 1; Caption = 'Windows 12 Pro'; Build = 99999; SKU = 48; Role = 'workstation'; Release = $null; Edition = 'pro' }
        @{ Label = 'unknown workstation build with Windows 11 caption'; ProductType = 1; Caption = 'Windows 11 Pro'; Build = 99999; SKU = 48; Role = 'workstation'; Release = $null; Edition = 'pro' }
        @{ Label = 'unknown future server'; ProductType = 3; Caption = 'Windows Server 2030'; Build = 99999; SKU = 8; Role = 'server'; Release = $null; Edition = 'datacenter' }
        @{ Label = 'unavailable product facts'; ProductType = 0; Caption = ''; Build = 0; SKU = 0; Role = $null; Release = $null; Edition = $null }
    ) {
        $context = @{ os = 'windows'; host = 'SERVER1'; windows = @{ ProductType = $ProductType; Caption = $Caption; BuildNumber = "$Build"; OperatingSystemSKU = $SKU } }
        $facts = & (Get-Module Homepsick) { param($Context) (Get-HomepsickMachineFact -Context $Context).Facts } $context
        $facts.windowsRole | Should -Be $Role
        $facts.windowsRelease | Should -Be $Release
        $facts.windowsEdition | Should -Be $Edition
        $facts.host | Should -Be 'server1'
        $facts.distro | Should -BeNullOrEmpty
    }

    It 'reports raw unknown Windows values while retaining independent known facts' {
        $result = & (Get-Module Homepsick) {
            Get-HomepsickMachineFact -Context @{
                os = 'windows'
                windows = @{ ProductType = 3; BuildNumber = '99999'; OperatingSystemSKU = 99998 }
            }
        }
        $result.Facts.windowsRole | Should -Be 'server'
        $result.Facts.windowsRelease | Should -Be $null
        $result.Facts.windowsEdition | Should -Be $null
        $result.Notes -join ' ' | Should -BeLike '*windowsRelease*windowsEdition*ProductType=''3''*BuildNumber=''99999''*OperatingSystemSKU=''99998''*'
    }

    It 'normalizes synthetic facts and discards facts belonging to another platform' {
        $facts = & (Get-Module Homepsick) {
            (Get-HomepsickMachineFact -MachineFacts @{ os = ' LINUX '; host = 'MACHINE1'; distroLike = @('Debian', 'Ubuntu'); windowsRelease = '11' }).Facts
        }
        $facts.os | Should -Be 'linux'
        $facts.distroLike | Should -Be @('debian', 'ubuntu')
        $facts.windowsRelease | Should -BeNullOrEmpty
    }
}

Describe 'Priority rules' {
    It 'scores explicitly declared <Field> conditions at every tier' -ForEach @(
        @{ Field = 'os'; Value = 'linux'; Other = 'windows'; Score = 100 }
        @{ Field = 'distroLike'; Value = 'debian'; Other = 'fedora'; Score = 1000 }
        @{ Field = 'windowsRole'; Value = 'server'; Other = 'workstation'; Score = 1000 }
        @{ Field = 'distro'; Value = 'ubuntu'; Other = 'fedora'; Score = 10000 }
        @{ Field = 'distroVersion'; Value = '24.04'; Other = '22.04'; Score = 10000 }
        @{ Field = 'windowsRelease'; Value = '11'; Other = '10'; Score = 10000 }
        @{ Field = 'windowsEdition'; Value = 'pro'; Other = 'enterprise'; Score = 10000 }
        @{ Field = 'host'; Value = 'machine1'; Other = 'machine2'; Score = 100000 }
    ) {
        $scalar = @{ $Field = $Value }
        $singleton = @{ $Field = @($Value) }
        $multiple = @{ $Field = @($Value, $Other) }
        & (Get-Module Homepsick) { param($When) Get-HomepsickRootPriority $When } $scalar | Should -Be $Score
        & (Get-Module Homepsick) { param($When) Get-HomepsickRootPriority $When } $singleton | Should -Be $Score
        & (Get-Module Homepsick) { param($When) Get-HomepsickRootPriority $When } $multiple | Should -Be ($Score / 2)
    }

    It 'adds independent conditions without inferred OS points' -ForEach @(
        @{ When = @{}; Expected = 0 }
        @{ When = @{ distro = 'ubuntu' }; Expected = 10000 }
        @{ When = @{ distro = 'ubuntu'; distroVersion = '24.04' }; Expected = 20000 }
        @{ When = @{ windowsRelease = '11'; windowsEdition = 'pro' }; Expected = 20000 }
        @{ When = @{ windowsRelease = 'server-2022'; windowsEdition = 'datacenter' }; Expected = 20000 }
        @{ When = @{ host = 'machine1'; os = 'windows' }; Expected = 100100 }
    ) {
        & (Get-Module Homepsick) { param($When) Get-HomepsickRootPriority $When } $When | Should -Be $Expected
    }
}
