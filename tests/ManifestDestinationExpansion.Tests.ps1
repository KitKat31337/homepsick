# Exercise lexical normalization and process-environment expansion on both hosts.
# All writes stay in TestDrive; environment changes are restored after every test.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psd1') -Force
    $script:expansionVariables = @('HOME', 'HOMEPSICK_DESTINATION_TEST', 'HOMEPSICK_SECOND_TEST', 'ProgramFiles(x86)', 'APPDATA')
    function Set-ExpansionManifest {
        param([string]$Path, [bool]$OutsideHome = $false, [object[]]$Roots = @(@{ source = 'shared'; target = 'config' }))
        @{ version = 1; roots = $Roots; destinations = @{ config = @{ path = $Path; outsideHome = $OutsideHome } } } |
            ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $castle.CastlePath 'homepsick.json')
    }
}

Describe 'Destination navigation and environment expansion' {
    BeforeEach {
        $savedEnvironment = @{}
        foreach ($name in $script:expansionVariables) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $env:HOME = Join-Path $fixture 'home'
        New-Item -ItemType Directory -Path $env:HOME -Force | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
        Remove-Item -LiteralPath $castle.CastleSymRoot
        New-Item -ItemType Directory -Path (Join-Path $castle.CastlePath 'shared') | Out-Null
        Set-Content -LiteralPath (Join-Path $castle.CastlePath 'shared/settings') -Value 'shared settings'
        & git -C $castle.CastlePath add shared/settings
        $inside = Join-Path $env:HOME 'AppData/Roaming'
        $outside = Join-Path $fixture 'external destination'
        [Environment]::SetEnvironmentVariable('HOMEPSICK_DESTINATION_TEST', $inside, 'Process')
        [Environment]::SetEnvironmentVariable('HOMEPSICK_SECOND_TEST', $null, 'Process')
    }

    AfterEach {
        foreach ($name in $script:expansionVariables) {
            [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
        }
    }

    It 'normalizes <Path> portably without consulting the filesystem' -ForEach @(
        @{ Path = '~/AppData/Roaming/../Local/Editor'; Expected = '~/AppData/Local/Editor' }
        @{ Path = 'C:\Users\alice\AppData\Roaming\..\Local\Editor'; Expected = 'C:/Users/alice/AppData/Local/Editor' }
        @{ Path = 'd:/config/sub/.././settings'; Expected = 'd:/config/settings' }
        @{ Path = '/etc/example/../other'; Expected = '/etc/other' }
    ) {
        $normalized = & (Get-Module Homepsick) { param($Value) ConvertTo-HomepsickDestination $Value } $Path
        $normalized.Path | Should -BeExactly $Expected
        Set-ExpansionManifest $Path -OutsideHome $true -Roots @()
        (Test-HomepsickManifest -CastleName configs).IsValid | Should -BeTrue
    }

    It 'rejects unsafe normalization of <Path> even when components would cancel' -ForEach @(
        @{ Path = '~/../outside' }
        @{ Path = '~/config/..' }
        @{ Path = 'D:/config/..' }
        @{ Path = '/etc/..' }
        @{ Path = '/etc/../../escape' }
        @{ Path = 'C:/config/.git/../settings' }
        @{ Path = 'C:/config/CON/../settings' }
        @{ Path = 'C:/config/bad./../settings' }
        @{ Path = 'C:/config//../settings' }
    ) {
        Set-ExpansionManifest $Path -OutsideHome $true -Roots @()
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'InvalidDestinationPath'
    }

    It 'expands <Path>, previews without writes, links, and tracks through the same mapping' -ForEach @(
        @{ Path = '%HOMEPSICK_DESTINATION_TEST%/../Local/Editor' }
        @{ Path = '$HOMEPSICK_DESTINATION_TEST/../Local/Editor' }
        @{ Path = '${HOMEPSICK_DESTINATION_TEST}/../Local/Editor' }
    ) {
        Set-ExpansionManifest $Path
        $manifest = Join-Path $castle.CastlePath 'homepsick.json'
        $hash = (Get-FileHash $manifest).Hash
        $expected = Join-Path $env:HOME 'AppData/Local/Editor/settings'
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -BeTrue
        $plan.Winners.DestinationPath | Should -Be ([IO.Path]::GetFullPath($expected))
        $plan.Winners.Allowed | Should -BeTrue
        Test-Path -LiteralPath (Split-Path -Parent $expected) | Should -BeFalse
        Enable-HomepsickCastle -CastleName configs -WhatIf
        Test-Path -LiteralPath $expected | Should -BeFalse
        Enable-HomepsickCastle -CastleName configs -Batch
        (Get-Item -LiteralPath $expected).LinkType | Should -Be 'SymbolicLink'
        Get-Content -LiteralPath $expected | Should -Be 'shared settings'
        $newFile = Join-Path (Split-Path -Parent $expected) 'tracked'
        Set-Content -LiteralPath $newFile -Value 'new settings'
        Add-HomepsickFile -CastleName configs -Path $newFile
        (& git -C $castle.CastlePath ls-files) | Should -Contain 'shared/tracked'
        (Get-Item -LiteralPath $newFile).LinkType | Should -Be 'SymbolicLink'
        (Get-FileHash $manifest).Hash | Should -Be $hash
    }

    It 'supports a variable alone and Windows variable names containing parentheses' {
        [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', ((Join-Path $env:HOME 'applications') + [IO.Path]::DirectorySeparatorChar), 'Process')
        Set-ExpansionManifest '%ProgramFiles(x86)%'
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -BeTrue
        $plan.Winners.DestinationPath | Should -Be (Join-Path $env:HOME 'applications/settings')
    }

    It 'follows native environment-name case rules' {
        Set-ExpansionManifest '$homepsick_destination_test/editor'
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -Be $IsWindows
        if (-not $IsWindows) { $plan.Errors.Message -join ' ' | Should -BeLike '*missing or empty*' }
    }

    It 'rejects unsupported variable syntax <Path> even in an unused declaration' -ForEach @(
        @{ Path = '${HOMEPSICK_DESTINATION_TEST:-fallback}/editor' }
        @{ Path = '$(Get-Location)/editor' }
        @{ Path = '$env:HOME/editor' }
        @{ Path = '%HOMEPSICK_DESTINATION_TEST%/%HOMEPSICK_SECOND_TEST%' }
        @{ Path = '$HOMEPSICK_DESTINATION_TEST/$HOMEPSICK_SECOND_TEST' }
        @{ Path = '${HOMEPSICK_DESTINATION_TEST}${HOMEPSICK_SECOND_TEST}' }
        @{ Path = '%HOMEPSICK_DESTINATION_TEST%/folder//editor' }
        @{ Path = '%HOMEPSICK_DESTINATION_TEST%/.git/../editor' }
    ) {
        Set-ExpansionManifest $Path -Roots @()
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'InvalidDestinationPath'
    }

    It 'rejects a selected variable containing <Label> before linking any files' -ForEach @(
        @{ Label = 'no value'; Value = $null }
        @{ Label = 'an empty value'; Value = '' }
        @{ Label = 'a relative path'; Value = 'relative/config' }
        @{ Label = 'a drive-relative path'; Value = 'C:config' }
        @{ Label = 'a UNC path'; Value = '\\server\share' }
        @{ Label = 'a drive root'; Value = 'D:\' }
        @{ Label = 'a reserved component that would cancel'; Value = 'C:/CON/../settings' }
    ) {
        [Environment]::SetEnvironmentVariable('HOMEPSICK_DESTINATION_TEST', $Value, 'Process')
        Set-ExpansionManifest '$HOMEPSICK_DESTINATION_TEST' -OutsideHome $true
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -BeFalse
        $plan.Errors.Code | Should -Contain 'InvalidDestination'
        { Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -Force -Batch } | Should -Throw '*InvalidDestination*'
        $plan.Winners | Should -BeNullOrEmpty
    }

    It 'does not look up variables for skipped entries, unused declarations, or static overlap warnings' {
        Set-ExpansionManifest '${HOMEPSICK_SECOND_TEST}/../editor' -Roots @(
            @{ source = 'shared'; target = 'config'; when = @{ host = 'other-machine' } }
            @{ source = 'absent'; target = 'config'; when = @{ host = 'other-machine' } }
        )
        Mock Resolve-HomepsickDestination -ModuleName Homepsick { throw 'Inactive variable was resolved.' }
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'linux'; host = 'this-machine' }
        $plan.IsValid | Should -BeTrue
        $plan.Warnings.Code | Should -Contain 'PotentialTie'
        $plan.Winners | Should -BeNullOrEmpty
        Should -Invoke Resolve-HomepsickDestination -ModuleName Homepsick -Times 0 -Exactly
        Set-ExpansionManifest '%HOMEPSICK_SECOND_TEST%' -Roots @()
        (Test-HomepsickManifest -CastleName configs).IsValid | Should -BeTrue
        Should -Invoke Resolve-HomepsickDestination -ModuleName Homepsick -Times 0 -Exactly
    }

    It 'rejects <Suffix> that escapes or resolves to the expanded filesystem root' -ForEach @(
        @{ Suffix = '/../escape' }
        @{ Suffix = '/child/..' }
    ) {
        [Environment]::SetEnvironmentVariable('HOMEPSICK_DESTINATION_TEST', [IO.Path]::GetPathRoot($env:HOME), 'Process')
        Set-ExpansionManifest ('%HOMEPSICK_DESTINATION_TEST%' + $Suffix) -OutsideHome $true
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -BeFalse
        $plan.Errors.Code | Should -Contain 'InvalidDestination'
        { Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -Force -Batch } | Should -Throw '*InvalidDestination*'
    }

    It 'does not hide repeated separators in environment value <Value> when joining a suffix' -ForEach @(
        @{ Value = '//' }
        @{ Value = '/tmp//' }
        @{ Value = 'C:\config\\' }
    ) {
        [Environment]::SetEnvironmentVariable('HOMEPSICK_DESTINATION_TEST', $Value, 'Process')
        Set-ExpansionManifest '%HOMEPSICK_DESTINATION_TEST%/editor' -OutsideHome $true
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'InvalidDestination'
    }

    It 'infers Windows eligibility without priority points from <Path>' -ForEach @(
        @{ Path = '%APPDATA%/../Local/Editor' }
        @{ Path = '$APPDATA/../Local/Editor' }
        @{ Path = '${APPDATA}/../Local/Editor' }
        @{ Path = '%LOCALAPPDATA%/Editor' }
        @{ Path = '%USERPROFILE%/Editor' }
    ) {
        Set-ExpansionManifest $Path
        Mock Resolve-HomepsickDestination -ModuleName Homepsick { throw 'Windows variable was resolved on Linux.' }
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'linux' }
        $plan.IsValid | Should -BeTrue
        $plan.Entries.Selected | Should -BeFalse
        $plan.Entries.CalculatedPriority | Should -Be 0
        $plan.Entries.Reasons -join ' ' | Should -BeLike '*requires OS*windows*'
        Should -Invoke Resolve-HomepsickDestination -ModuleName Homepsick -Times 0 -Exactly
        Set-ExpansionManifest $Path -Roots @(@{ source = 'shared'; target = 'config'; when = @{ os = 'linux' } })
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'UnreachableEntry'
    }

    It 'resolves redirected Windows AppData using injected Windows facts on either host' {
        [Environment]::SetEnvironmentVariable('APPDATA', 'd:\Redirected Profiles\alice\Roaming', 'Process')
        Set-ExpansionManifest '%APPDATA%\..\Local\Editor' -OutsideHome $true
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'windows' }
        $plan.Entries.Selected | Should -BeTrue
        $plan.IsValid | Should -Be $IsWindows
        if ($IsWindows) { $plan.Winners.DestinationPath | Should -Be 'd:\Redirected Profiles\alice\Local\Editor\settings' }
        else { $plan.Errors.Message -join ' ' | Should -BeLike '*another platform*' }
    }

    It 'requires both external authorizations after expansion and preserves conflicts' {
        [Environment]::SetEnvironmentVariable('HOMEPSICK_DESTINATION_TEST', (Join-Path $outside 'Roaming'), 'Process')
        Set-ExpansionManifest '%HOMEPSICK_DESTINATION_TEST%/../Local'
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'OutsideHomeDeclaration'
        Set-ExpansionManifest '%HOMEPSICK_DESTINATION_TEST%/../Local' -OutsideHome $true
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -BeTrue
        $plan.Winners.Allowed | Should -BeFalse
        Enable-HomepsickCastle -CastleName configs -Force -Batch -WarningAction SilentlyContinue
        Test-Path -LiteralPath $outside | Should -BeFalse
        Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -WhatIf
        Test-Path -LiteralPath $outside | Should -BeFalse
        $directory = Join-Path $outside 'Local'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $file = Join-Path $directory 'settings'
        Set-Content -LiteralPath $file -Value 'keep existing'
        (Get-HomepsickLinkPlan -CastleName configs -AllowOutsideHome).Conflicts.Count | Should -Be 1
        Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -Batch -WarningAction SilentlyContinue
        Get-Content -LiteralPath $file | Should -Be 'keep existing'
        Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -Force -Batch
        Get-Content -LiteralPath $file | Should -Be 'shared settings'
    }

    It 'detects aliases between expanded and literal destinations before writing' {
        Set-ExpansionManifest '~/AppData/Local/Editor' -Roots @()
        $manifestPath = Join-Path $castle.CastlePath 'homepsick.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
        $manifest.destinations.expanded = @{ path = '$HOMEPSICK_DESTINATION_TEST/../Local/Editor' }
        $manifest.roots = @(@{ source = 'shared'; target = 'config' }, @{ source = 'shared'; target = 'expanded' })
        $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.Errors.Code | Should -Contain 'PriorityTie'
        { Enable-HomepsickCastle -CastleName configs -Batch } | Should -Throw '*PriorityTie*'
        Test-Path -LiteralPath (Join-Path $env:HOME 'AppData') | Should -BeFalse
    }

    It 'retains managed ownership for an inactive root sharing an active environment destination' {
        New-Item -ItemType Directory -Path (Join-Path $castle.CastlePath 'overlay') | Out-Null
        Set-Content -LiteralPath (Join-Path $castle.CastlePath 'overlay/settings') -Value 'overlay settings'
        & git -C $castle.CastlePath add overlay/settings
        Set-ExpansionManifest '$HOMEPSICK_DESTINATION_TEST/editor' -Roots @(
            @{ source = 'shared'; target = 'config'; when = @{ host = 'base' } }
            @{ source = 'overlay'; target = 'config'; when = @{ host = 'overlay' } }
        )
        Enable-HomepsickCastle -CastleName configs -MachineFacts @{ host = 'base' } -Batch
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ host = 'overlay' }
        $plan.IsValid | Should -BeTrue
        $plan.Winners.ExistingState | Should -Be 'ManagedLink'
        Enable-HomepsickCastle -CastleName configs -MachineFacts @{ host = 'overlay' } -Batch
        Get-Content -LiteralPath (Join-Path $inside 'editor/settings') | Should -Be 'overlay settings'
    }

    It 'does not evaluate or recursively expand environment values' {
        $literalDirectory = Join-Path $env:HOME '$(throw should-not-run)-$HOMEPSICK_SECOND_TEST'
        [Environment]::SetEnvironmentVariable('HOMEPSICK_DESTINATION_TEST', $literalDirectory, 'Process')
        Set-ExpansionManifest '$HOMEPSICK_DESTINATION_TEST/editor'
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -BeTrue
        $plan.Winners.DestinationPath | Should -Be (Join-Path $literalDirectory 'editor/settings')
        Enable-HomepsickCastle -CastleName configs -Batch
        Get-Content -LiteralPath (Join-Path $literalDirectory 'editor/settings') | Should -Be 'shared settings'
    }

    It 'blocks symlink parents and castle storage after expansion and normalization' {
        New-Item -ItemType Directory -Path $outside | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $env:HOME 'redirect') -Target $outside | Out-Null
        [Environment]::SetEnvironmentVariable('HOMEPSICK_DESTINATION_TEST', (Join-Path $env:HOME 'redirect/temporary'), 'Process')
        Set-ExpansionManifest '%HOMEPSICK_DESTINATION_TEST%/../editor'
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'UnsafeDestination'
        { Enable-HomepsickCastle -CastleName configs -Force -Batch } | Should -Throw '*UnsafeDestination*'
        @(Get-ChildItem -LiteralPath $outside).Count | Should -Be 0
        [Environment]::SetEnvironmentVariable('HOMEPSICK_DESTINATION_TEST', $castle.CastlePath, 'Process')
        Set-ExpansionManifest '$HOMEPSICK_DESTINATION_TEST/nested'
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'CastleStorageDestination'
    }
}
