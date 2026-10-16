# Exercises destination-to-root tracking, actual link winners, and per-file rollback.
# Real Git indexes expose staged-data loss that filesystem assertions alone would miss.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psd1') -Force
    $script:previousHome = $env:HOME
    function Set-TrackingManifest {
        # Remove layout assumptions: these fixtures may omit home and reuse conditional sources.
        param([object[]]$Roots, $Destinations = @{})
        @{ version = 1; roots = $Roots; destinations = $Destinations } | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $castle.CastlePath 'homepsick.json')
    }
    function New-TrackingFile {
        # Create destination-side data or source/index fixtures without implicitly staging them.
        param([string]$Path, [string]$Value = 'user settings')
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
        Set-Content -LiteralPath $Path -Value $Value
        return $Path
    }
    function Get-TrackingIndex {
        # Snapshot staged modes and blob IDs, not just names, to detect lost prior index content.
        (& git -C $castle.CastlePath ls-files --stage) -join "`n"
    }
}
AfterAll { $env:HOME = $script:previousHome }

Describe 'Tracking into manifest roots' {
    BeforeEach {
        $env:HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $env:HOME | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
        Remove-Item -LiteralPath $castle.CastleSymRoot
    }

    It 'tracks into a castle without home, stages the mapped path, and links back' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home'; into = '.config/editor' })
        $inputFile = New-TrackingFile (Join-Path $env:HOME '.config/editor/settings.json')
        Add-HomepsickFile -CastleName configs -Path $inputFile
        Test-Path -LiteralPath $castle.CastleSymRoot | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $castle.CastlePath 'editor/settings.json') | Should -Be 'user settings'
        (Get-Item -LiteralPath $inputFile -Force).LinkType | Should -Be 'SymbolicLink'
        (& git -C $castle.CastlePath diff --cached --name-only) | Should -Be 'editor/settings.json'
        (Get-HomepsickLinkPlan -CastleName configs).Winners.ExistingState | Should -Be 'AlreadyLinked'
    }

    # Supply both platform contexts on each host so root choice never depends on
    # the CI machine, while link creation still uses native paths.
    It 'selects conditional roots using synthetic <OS> facts on either host' -ForEach @(
        @{ OS = 'windows'; RootName = 'windows'; Facts = @{ os = 'windows'; windowsRelease = '11'; windowsEdition = 'pro' } }
        @{ OS = 'linux'; RootName = 'ubuntu'; Facts = @{ os = 'linux'; distro = 'ubuntu'; distroVersion = '24.04' } }
    ) {
        Set-TrackingManifest @(
            @{ source = 'windows'; target = 'home'; into = '.config/editor'; when = @{ windowsRelease = '11'; windowsEdition = 'pro' } }
            @{ source = 'ubuntu'; target = 'home'; into = '.config/editor'; when = @{ distro = 'ubuntu'; distroVersion = '24.04' } }
        )
        $inputFile = New-TrackingFile (Join-Path $env:HOME '.config/editor/settings')
        Add-HomepsickFile -CastleName configs -Path $inputFile -MachineFacts $Facts
        (& git -C $castle.CastlePath diff --cached --name-only) | Should -Be "$RootName/settings"
    }

    It 'requires a root choice for overlapping mappings regardless of their priority' {
        Set-TrackingManifest @(@{ source = 'one'; target = 'home'; priority = 1 }, @{ source = 'two'; target = 'home'; priority = 2 })
        $inputFile = New-TrackingFile (Join-Path $env:HOME 'settings')
        { Add-HomepsickFile -CastleName configs -Path $inputFile } | Should -Throw '*AmbiguousTrackingRoot*roots`[0`]*roots`[1`]*'
        Get-Content -LiteralPath $inputFile | Should -Be 'user settings'
        Get-TrackingIndex | Should -BeNullOrEmpty
        Add-HomepsickFile -CastleName configs -Path $inputFile -Root 'roots[1]'
        (& git -C $castle.CastlePath diff --cached --name-only) | Should -Be 'two/settings'
    }

    It 'requires a choice between implicit home and an overlay' {
        New-Item -ItemType Directory -Path $castle.CastleSymRoot | Out-Null
        Set-TrackingManifest @(@{ source = 'overlay'; target = 'home'; when = @{ os = 'linux' } })
        $inputFile = New-TrackingFile (Join-Path $env:HOME 'settings')
        { Add-HomepsickFile -CastleName configs -Path $inputFile -MachineFacts @{ os = 'linux' } } | Should -Throw '*AmbiguousTrackingRoot*implicit home*roots`[0`]*'
        Add-HomepsickFile -CastleName configs -Path $inputFile -Root overlay -MachineFacts @{ os = 'linux' }
        (& git -C $castle.CastlePath diff --cached --name-only) | Should -Be 'overlay/settings'
    }

    It 'refuses an explicitly chosen root that does not currently apply' {
        Set-TrackingManifest @(@{ source = 'windows'; target = 'home'; when = @{ os = 'windows' } })
        $inputFile = New-TrackingFile (Join-Path $env:HOME 'settings')
        { Add-HomepsickFile -CastleName configs -Path $inputFile -Root windows -MachineFacts @{ os = 'linux' } } | Should -Throw '*NoTrackingRoot*'
        Get-Content -LiteralPath $inputFile | Should -Be 'user settings'
    }

    It 'uses mutually exclusive shared-source destination mappings for <OS>' -ForEach @(
        @{ OS = 'windows'; Into = 'AppData/Roaming/Editor' }
        @{ OS = 'linux'; Into = '.config/editor' }
    ) {
        Set-TrackingManifest @(
            @{ source = 'editor'; target = 'home'; into = 'AppData/Roaming/Editor'; when = @{ os = 'windows' } }
            @{ source = 'editor'; target = 'home'; into = '.config/editor'; when = @{ os = 'linux' } }
        )
        $inputFile = New-TrackingFile (Join-Path $env:HOME "$Into/settings")
        Add-HomepsickFile -CastleName configs -Path $inputFile -Root editor -MachineFacts @{ os = $OS }
        (& git -C $castle.CastlePath diff --cached --name-only) | Should -Be 'editor/settings'
        (Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = $OS }).Winners.DestinationPath | Should -Be $inputFile
    }

    It 'requires an entry identifier when a shared source has two qualifying mappings' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home'; into = '.config' }, @{ source = 'editor'; target = 'home'; into = '.config/editor'; priority = 1 })
        $inputFile = New-TrackingFile (Join-Path $env:HOME '.config/editor/settings')
        { Add-HomepsickFile -CastleName configs -Path $inputFile -Root editor } | Should -Throw '*AmbiguousTrackingRoot*'
        Add-HomepsickFile -CastleName configs -Path $inputFile -Root 'roots[1]'
        (& git -C $castle.CastlePath diff --cached --name-only) | Should -Be 'editor/settings'
    }

    # Storage intent and link precedence are separate: adding to a lower root
    # must not bypass a higher-priority tracked file already providing this destination.
    It 'stores the chosen root while linking back to the shared plan winner' {
        Set-TrackingManifest @(@{ source = 'lower'; target = 'home'; priority = 1 }, @{ source = 'higher'; target = 'home'; priority = 2 })
        New-TrackingFile (Join-Path $castle.CastlePath 'higher/settings') 'winning settings' | Out-Null
        & git -C $castle.CastlePath add higher/settings
        $inputFile = New-TrackingFile (Join-Path $env:HOME 'settings')
        Add-HomepsickFile -CastleName configs -Path $inputFile -Root lower
        Get-Content -LiteralPath (Join-Path $castle.CastlePath 'lower/settings') | Should -Be 'user settings'
        Get-Content -LiteralPath $inputFile | Should -Be 'winning settings'
        (Get-HomepsickLinkPlan -CastleName configs).Winners.ExistingState | Should -Be 'AlreadyLinked'
    }

    It 'tracks a directory, preserves nested names, and skips already stored files' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home'; into = '.config/editor' })
        $directory = Join-Path $env:HOME '.config/editor'
        New-TrackingFile (Join-Path $directory 'folder with spaces/one') 'one' | Out-Null
        New-TrackingFile (Join-Path $directory 'two') 'two' | Out-Null
        Add-HomepsickFile -CastleName configs -Path $directory
        Add-HomepsickFile -CastleName configs -Path $directory
        @(& git -C $castle.CastlePath diff --cached --name-only).Count | Should -Be 2
        Get-Content -LiteralPath (Join-Path $directory 'folder with spaces/one') | Should -Be 'one'
    }

    It 'does not move, stage, or create directories under WhatIf' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home'; into = '.config/editor' })
        $inputFile = New-TrackingFile (Join-Path $env:HOME '.config/editor/settings')
        Add-HomepsickFile -CastleName configs -Path $inputFile -WhatIf
        Get-TrackingIndex | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $castle.CastlePath 'editor') | Should -BeFalse
        (Get-Item -LiteralPath $inputFile).LinkType | Should -BeNullOrEmpty
    }

    It 'honors ignore rules for the selected source path' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home' })
        Set-Content -LiteralPath (Join-Path $castle.CastlePath '.gitignore') -Value 'editor/settings'
        $inputFile = New-TrackingFile (Join-Path $env:HOME 'settings')
        Add-HomepsickFile -CastleName configs -Path $inputFile -WarningAction SilentlyContinue
        Get-TrackingIndex | Should -BeNullOrEmpty
        (Get-Item -LiteralPath $inputFile).LinkType | Should -BeNullOrEmpty
    }

    It 'requires external opt in for tracking and supports external WhatIf' {
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Set-TrackingManifest @(@{ source = 'system'; target = 'systemConfig' }) @{ systemConfig = @{ path = $outside.Replace('\', '/'); outsideHome = $true } }
        $inputFile = New-TrackingFile (Join-Path $outside 'settings')
        { Add-HomepsickFile -CastleName configs -Path $inputFile } | Should -Throw '*OutsideHomeOptIn*roots`[0`]*'
        Add-HomepsickFile -CastleName configs -Path $inputFile -AllowOutsideHome -WhatIf
        Get-TrackingIndex | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $castle.CastlePath 'system') | Should -BeFalse
        Add-HomepsickFile -CastleName configs -Path $inputFile -AllowOutsideHome
        (Get-Item -LiteralPath $inputFile -Force).LinkType | Should -Be 'SymbolicLink'
        (& git -C $castle.CastlePath diff --cached --name-only) | Should -Be 'system/settings'
    }

    It 'rejects a destination symlink parent before moving any files' {
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-TrackingFile (Join-Path $outside 'editor/settings') | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $env:HOME '.config') -Target $outside | Out-Null
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home'; into = '.config/editor' })
        { Add-HomepsickFile -CastleName configs -Path (Join-Path $env:HOME '.config/editor/settings') } | Should -Throw '*UnsafeTrackingPath*Symbolic link*'
        Get-Content -LiteralPath (Join-Path $outside 'editor/settings') | Should -Be 'user settings'
        Get-TrackingIndex | Should -BeNullOrEmpty
    }

    It 'validates a directory symlink before moving any files from a directory input' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home'; into = '.config/editor' })
        $directory = Join-Path $env:HOME '.config/editor'
        $good = New-TrackingFile (Join-Path $directory 'good')
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $kept = New-TrackingFile (Join-Path $outside 'keep')
        New-Item -ItemType SymbolicLink -Path (Join-Path $directory 'linked') -Target $outside | Out-Null
        { Add-HomepsickFile -CastleName configs -Path $directory } | Should -Throw '*UnsafeTrackingPath*Directory symbolic links*'
        Get-Content -LiteralPath $good | Should -Be 'user settings'
        (Get-Item -LiteralPath $good).LinkType | Should -BeNullOrEmpty
        Get-Content -LiteralPath $kept | Should -Be 'user settings'
        Get-TrackingIndex | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $castle.CastlePath 'editor') | Should -BeFalse
    }

    It 'refuses tracking a castle-storage file through a home destination mapping' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home' })
        $inputFile = New-TrackingFile (Join-Path $castle.CastlePath 'keep')
        { Add-HomepsickFile -CastleName configs -Path $inputFile } | Should -Throw '*CastleStorageDestination*'
        Get-Content -LiteralPath $inputFile | Should -Be 'user settings'
        Get-TrackingIndex | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $castle.CastlePath 'editor') | Should -BeFalse
    }

    It 'rolls back an unsafe relative source link without losing its original target' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home'; into = '.config/editor' })
        New-TrackingFile (Join-Path $env:HOME '.config/other') | Out-Null
        $inputFile = Join-Path $env:HOME '.config/editor/settings'
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputFile) | Out-Null
        New-Item -ItemType SymbolicLink -Path $inputFile -Target '../other' | Out-Null
        $originalLinkTarget = @((Get-Item -LiteralPath $inputFile -Force).Target)[0]
        { Add-HomepsickFile -CastleName configs -Path $inputFile } | Should -Throw '*UnsafeSourceLink*roots`[0`]*'
        @((Get-Item -LiteralPath $inputFile -Force).Target)[0] | Should -Be $originalLinkTarget
        Get-Content -LiteralPath $inputFile | Should -Be 'user settings'
        Get-TrackingIndex | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $castle.CastlePath 'editor/settings') | Should -BeFalse
    }

    # Fail at external boundaries after staging, then assert original file contents,
    # link type, and the entire prior index. Unrelated staged work is part of the contract.
    It 'restores files and unrelated staged work when link creation fails after staging' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home' })
        New-TrackingFile (Join-Path $castle.CastlePath 'unrelated') 'unrelated work' | Out-Null
        & git -C $castle.CastlePath add unrelated
        $indexBefore = Get-TrackingIndex
        $inputFile = New-TrackingFile (Join-Path $env:HOME 'settings')
        Mock New-Item { throw 'Simulated link failure' } -ModuleName Homepsick -ParameterFilter { $ItemType -eq 'SymbolicLink' }
        { Add-HomepsickFile -CastleName configs -Path $inputFile } | Should -Throw '*Simulated link failure*'
        Get-Content -LiteralPath $inputFile | Should -Be 'user settings'
        (Get-Item -LiteralPath $inputFile).LinkType | Should -BeNullOrEmpty
        Get-TrackingIndex | Should -Be $indexBefore
        Test-Path -LiteralPath (Join-Path $castle.CastlePath 'editor/settings') | Should -BeFalse
    }

    It 'keeps the original file when moving it fails' {
        Set-TrackingManifest @(@{ source = 'editor'; target = 'home' })
        $inputFile = New-TrackingFile (Join-Path $env:HOME 'settings')
        Mock Move-Item { throw 'Simulated move failure' } -ModuleName Homepsick
        { Add-HomepsickFile -CastleName configs -Path $inputFile } | Should -Throw '*Simulated move failure*'
        Get-Content -LiteralPath $inputFile | Should -Be 'user settings'
        Get-TrackingIndex | Should -BeNullOrEmpty
    }

    It 'preserves the existing no-manifest home tracking behavior and restrictions' {
        New-Item -ItemType Directory -Path $castle.CastleSymRoot | Out-Null
        $inputFile = New-TrackingFile (Join-Path $env:HOME 'settings')
        Add-HomepsickFile -CastleName configs -Path $inputFile
        (& git -C $castle.CastlePath diff --cached --name-only) | Should -Be 'home/settings'
        Get-Content -LiteralPath $inputFile | Should -Be 'user settings'
        $outsideFile = New-TrackingFile (Join-Path $TestDrive 'outside-settings')
        { Add-HomepsickFile -CastleName configs -Path $outsideFile -AllowOutsideHome } | Should -Throw '*must be inside the home directory*'
    }

    # Leave a blob in the index after removing its working file. A failed git add
    # must restore that exact prior blob, not merely unstage the new content.
    It 'restores a preexisting index entry if staging modifies it then fails' {
        New-Item -ItemType Directory -Path $castle.CastleSymRoot | Out-Null
        $stored = New-TrackingFile (Join-Path $castle.CastleSymRoot 'settings') 'previously staged'
        New-TrackingFile (Join-Path $castle.CastlePath 'unrelated') 'unrelated staged work' | Out-Null
        & git -C $castle.CastlePath add .
        $indexBefore = Get-TrackingIndex
        Remove-Item -LiteralPath $stored
        $inputFile = New-TrackingFile (Join-Path $env:HOME 'settings')
        Mock Invoke-HomepsickGit {
            & git -C $RepositoryPath @Arguments | Out-Null
            throw 'Simulated staging failure after index change'
        } -ModuleName Homepsick -ParameterFilter { $Arguments[0] -eq 'add' }
        { Add-HomepsickFile -CastleName configs -Path $inputFile } | Should -Throw '*Simulated staging failure*'
        Get-TrackingIndex | Should -Be $indexBefore
        Get-Content -LiteralPath $inputFile | Should -Be 'user settings'
        (Get-Item -LiteralPath $inputFile).LinkType | Should -BeNullOrEmpty
        Test-Path -LiteralPath $stored | Should -BeFalse
    }

    It 'stages a manifest root inside an initialized submodule in its own index' {
        $moduleSource = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        & git init --initial-branch=main $moduleSource | Out-Null
        & git -C $moduleSource config user.email 'tests@example.invalid'
        & git -C $moduleSource config user.name 'Homepsick Tests'
        New-TrackingFile (Join-Path $moduleSource 'existing') 'existing settings' | Out-Null
        & git -C $moduleSource add .
        & git -C $moduleSource commit -m 'Initial submodule' | Out-Null
        $previousProtocols = $env:GIT_ALLOW_PROTOCOL
        $env:GIT_ALLOW_PROTOCOL = 'file'
        try {
            & git -C $castle.CastlePath submodule add $moduleSource shared | Out-Null
            Set-TrackingManifest @(@{ source = 'shared'; target = 'home'; into = '.config/shared' })
            $indexBefore = Get-TrackingIndex
            $inputFile = New-TrackingFile (Join-Path $env:HOME '.config/shared/new')
            Add-HomepsickFile -CastleName configs -Path $inputFile
            (& git -C (Join-Path $castle.CastlePath 'shared') diff --cached --name-only) | Should -Be 'new'
            Get-TrackingIndex | Should -Be $indexBefore
            Get-Content -LiteralPath $inputFile | Should -Be 'user settings'
            @((Get-HomepsickLinkPlan -CastleName configs).Winners | Where-Object RepositoryRelativePath -eq 'shared/new').Count | Should -Be 1
        }
        finally { $env:GIT_ALLOW_PROTOCOL = $previousProtocols }
    }
}
