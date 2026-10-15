# Exercises the shared selection/overlay engine through preview and real links,
# preserving legacy castles and cross-castle conflict behavior.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psd1') -Force
    $script:previousHome = $env:HOME
    function Set-TestManifest {
        # Keep conditions as supplied so scalar and singleton normalization are exercised.
        param($Castle, $Roots, $Destinations = @{})
        @{ version = 1; roots = @($Roots); destinations = $Destinations } | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $Castle.CastlePath 'homepsick.json')
    }
    function Add-TestTrackedFile {
        # Stage real files; filesystem enumeration alone must not create candidates.
        param($Castle, [string]$Path, [string]$Value = 'settings')
        $file = Join-Path $Castle.CastlePath $Path
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($file)) -Force | Out-Null
        Set-Content -LiteralPath $file -Value $Value
        & git -C $Castle.CastlePath add -- $Path
        if ($LASTEXITCODE) { throw 'Failed to stage fixture.' }
    }
}
AfterAll { $env:HOME = $script:previousHome }

Describe 'Manifest selection and shared linking plan' {
    BeforeEach {
        $env:HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $env:HOME | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
    }

    It 'preserves implicit home and ignores other directories without a manifest' {
        Add-TestTrackedFile $castle 'home/example' 'home'
        Add-TestTrackedFile $castle 'home_linux/example' 'overlay'
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.HasManifest | Should -BeFalse
        $plan.Winners.Count | Should -Be 1
        $plan.Winners.Priority | Should -Be 0
        Enable-HomepsickCastle -CastleName configs -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'home'
    }

    # Synthetic facts change selection only; all filesystem checks still use the
    # executing OS, which keeps the same overlay scenarios portable between CI jobs.
    It 'applies AND across fields and OR within arrays, including singleton arrays' {
        Add-TestTrackedFile $castle 'overlay/example'
        Set-TestManifest $castle @(@{ source = 'overlay'; target = 'home'; when = @{ os = @('linux'); distro = @('ubuntu', 'fedora'); distroVersion = '24.04'; distroLike = @('rhel', 'debian'); host = 'machine1' } })
        $facts = @{ os = 'linux'; distro = 'ubuntu'; distroVersion = '24.04'; distroLike = @('debian', 'linux'); host = 'machine1' }
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts $facts
        $plan.Winners.Count | Should -Be 1
        $plan.Winners.Priority | Should -Be 115600
        $facts.host = 'another'
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts $facts
        $plan.Winners.Count | Should -Be 0
        ($plan.Entries | Where-Object Source -eq overlay).Reasons -join ' ' | Should -BeLike '*host*does not match*'
    }

    It 'requires the relevant platform without adding OS points' -ForEach @(
        @{ When = @{ distro = 'ubuntu' }; Facts = @{ os = 'linux'; distro = 'ubuntu' }; OtherOS = 'windows' }
        @{ When = @{ windowsRelease = '11' }; Facts = @{ os = 'windows'; windowsRelease = '11' }; OtherOS = 'linux' }
        @{ When = @{ windowsEdition = 'pro' }; Facts = @{ os = 'windows'; windowsEdition = 'pro' }; OtherOS = 'linux' }
    ) {
        Add-TestTrackedFile $castle 'overlay/example'
        Set-TestManifest $castle @(@{ source = 'overlay'; target = 'home'; when = $When })
        (Get-HomepsickLinkPlan -CastleName configs -MachineFacts $Facts).Winners.Priority | Should -Be 10000
        $Facts.os = $OtherOS
        (Get-HomepsickLinkPlan -CastleName configs -MachineFacts $Facts).Winners.Count | Should -Be 0
    }

    It 'matches Windows role, release, and edition arrays independently with AND' {
        Add-TestTrackedFile $castle 'overlay/example'
        Set-TestManifest $castle @(@{
            source = 'overlay'; target = 'home'
            when = @{ windowsRole = @('workstation'); windowsRelease = @('10', '11'); windowsEdition = @('pro', 'enterprise') }
        })
        $facts = @{ os = 'windows'; windowsRole = 'workstation'; windowsRelease = '11'; windowsEdition = 'pro' }
        (Get-HomepsickLinkPlan -CastleName configs -MachineFacts $facts).Winners.Priority | Should -Be 11000
        $facts.windowsEdition = 'home'
        (Get-HomepsickLinkPlan -CastleName configs -MachineFacts $facts).Winners.Count | Should -Be 0
    }

    It 'treats case-distinct Linux destinations as distinct files' -Skip:$IsWindows {
        Add-TestTrackedFile $castle 'overlay/name' 'lowercase'
        Add-TestTrackedFile $castle 'overlay/Name' 'uppercase'
        Set-TestManifest $castle @(@{ source = 'overlay'; target = 'home' })
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.Winners.Count | Should -Be 2
        $link = Join-Path $env:HOME 'name'
        New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $castle.CastlePath 'overlay/Name') | Out-Null
        (Get-HomepsickLinkPlan -CastleName configs).Conflicts.Count | Should -Be 1
        Enable-HomepsickCastle -CastleName configs -Force -Batch
        Get-Content -LiteralPath $link | Should -Be 'lowercase'
        Get-Content -LiteralPath (Join-Path $env:HOME 'Name') | Should -Be 'uppercase'
    }

    It 'skips entries whose future release fact is unavailable and explains why' {
        Add-TestTrackedFile $castle 'overlay/example'
        Set-TestManifest $castle @(@{ source = 'overlay'; target = 'home'; when = @{ windowsRelease = '12' } })
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'windows'; windowsRole = 'workstation' }
        $plan.IsValid | Should -BeTrue
        $plan.Winners.Count | Should -Be 0
        ($plan.Entries | Where-Object Source -eq overlay).Reasons -join ' ' | Should -BeLike '*windowsRelease*unavailable*'
    }

    # Competing files, rather than merely overlapping declarations, establish an
    # actual tie. Reversing declaration order proves there is no order-based winner.
    It 'reports release and edition ties before creating any link, independent of order' {
        Add-TestTrackedFile $castle 'release/example' 'release'
        Add-TestTrackedFile $castle 'edition/example' 'edition'
        Add-TestTrackedFile $castle 'home/unrelated' 'must not be linked either'
        $roots = @(@{ source = 'release'; target = 'home'; when = @{ windowsRelease = '11' } }, @{ source = 'edition'; target = 'home'; when = @{ windowsEdition = 'pro' } })
        foreach ($orderedRoots in @($roots, @($roots[1], $roots[0]))) {
            Set-TestManifest $castle $orderedRoots
            $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'windows'; windowsRelease = '11'; windowsEdition = 'pro' }
            $plan.Ties.Count | Should -Be 2
            $plan.Errors.Code | Should -Contain 'PriorityTie'
            $plan.Warnings.Code | Should -Contain 'PotentialTie'
            { Enable-HomepsickCastle -CastleName configs -Force -MachineFacts @{ os = 'windows'; windowsRelease = '11'; windowsEdition = 'pro' } } | Should -Throw '*Equal priority*'
            Test-Path -LiteralPath (Join-Path $env:HOME 'unrelated') | Should -BeFalse
        }
    }

    It 'lets combined conditions win and reports every shadowed candidate' -ForEach @(
        @{ Release = '11'; Edition = 'pro' }
        @{ Release = 'server-2022'; Edition = 'datacenter' }
    ) {
        Add-TestTrackedFile $castle 'release/example' 'release'
        Add-TestTrackedFile $castle 'edition/example' 'edition'
        Add-TestTrackedFile $castle 'combined/example' 'combined'
        Set-TestManifest $castle @(
            @{ source = 'release'; target = 'home'; when = @{ windowsRelease = $Release } }
            @{ source = 'edition'; target = 'home'; when = @{ windowsEdition = $Edition } }
            @{ source = 'combined'; target = 'home'; when = @{ windowsRelease = $Release; windowsEdition = $Edition } }
        )
        $facts = @{ os = 'windows'; windowsRelease = $Release; windowsEdition = $Edition }
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts $facts
        $plan.IsValid | Should -BeTrue
        $plan.Winners.Priority | Should -Be 20000
        $plan.Shadowed.Count | Should -Be 2
        $plan.Ties.Count | Should -Be 0
        Enable-HomepsickCastle -CastleName configs -Batch -MachineFacts $facts -WarningAction SilentlyContinue
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'combined'
    }

    It 'replaces the entire calculated score with an absolute priority, including negative values' {
        Add-TestTrackedFile $castle 'home/example' 'home'
        Add-TestTrackedFile $castle 'overlay/example' 'overlay'
        Set-TestManifest $castle @(@{ source = 'overlay'; target = 'home'; when = @{ host = 'machine1'; os = 'windows' }; priority = -1 })
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'windows'; host = 'machine1' }
        $plan.Shadowed.Priority | Should -Be -1
        $plan.Shadowed.CalculatedPriority | Should -Be 100100
        $plan.Shadowed.PriorityOverridden | Should -BeTrue
        $plan.Winners.RepositoryRelativePath | Should -Be 'home/example'
        Set-TestManifest $castle @(@{ source = 'overlay'; target = 'home'; when = @{ os = 'windows' }; priority = 75000 })
        (Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'windows' }).Winners.Priority | Should -Be 75000
    }

    It 'configures explicit home once and allows a manifest castle without home' {
        Add-TestTrackedFile $castle 'home/example'
        Set-TestManifest $castle @(@{ source = 'home'; target = 'home'; into = '.config'; priority = 17 })
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.Entries.Count | Should -Be 1
        $plan.Winners.Priority | Should -Be 17
        $plan.Winners.DestinationPath | Should -Be (Join-Path $env:HOME '.config/example')
        Remove-Item -LiteralPath $castle.CastleSymRoot -Recurse -Force
        & git -C $castle.CastlePath rm --cached home/example | Out-Null
        Add-TestTrackedFile $castle 'editor/example'
        Set-TestManifest $castle @(@{ source = 'editor'; target = 'home'; into = '.config/editor' })
        Enable-HomepsickCastle -CastleName configs -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME '.config/editor/example') | Should -Be 'settings'
        @($castle.ItemsToLink()).Count | Should -Be 1
    }

    It 'maps one source root to different destinations under exclusive conditions' {
        Add-TestTrackedFile $castle 'editor/settings.json'
        Set-TestManifest $castle @(
            @{ source = 'editor'; target = 'home'; into = 'AppData/Roaming/Editor'; when = @{ os = 'windows' } }
            @{ source = 'editor'; target = 'home'; into = '.config/editor'; when = @{ os = 'linux' } }
        )
        $windows = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'windows' }
        $linux = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'linux' }
        $windows.Winners.Count | Should -Be 1
        $linux.Winners.Count | Should -Be 1
        $windows.Winners.DestinationPath | Should -Be (Join-Path $env:HOME 'AppData/Roaming/Editor/settings.json')
        $linux.Winners.DestinationPath | Should -Be (Join-Path $env:HOME '.config/editor/settings.json')
        $linux.Warnings.Count | Should -Be 0
    }

    It 'updates a verified link when the winning root changes within one castle' {
        Add-TestTrackedFile $castle 'home/example' 'home'
        Add-TestTrackedFile $castle 'overlay/example' 'overlay'
        Set-TestManifest $castle @(@{ source = 'overlay'; target = 'home'; when = @{ os = 'linux' } })
        Enable-HomepsickCastle -CastleName configs -Batch -MachineFacts @{ os = 'windows' }
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'linux' }
        $plan.Winners.ExistingState | Should -Be 'ManagedLink'
        Enable-HomepsickCastle -CastleName configs -Batch -MachineFacts @{ os = 'linux' } -WhatIf
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'home'
        Enable-HomepsickCastle -CastleName configs -Batch -MachineFacts @{ os = 'linux' }
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'overlay'
    }

    It 'preserves batch, skip, force, and preview conflicts across different castles' {
        Add-TestTrackedFile $castle 'overlay/example' 'first'
        Set-TestManifest $castle @(@{ source = 'overlay'; target = 'home'; priority = 1000000 })
        Enable-HomepsickCastle -CastleName configs -Batch
        $second = New-HomepsickCastle -CastleName second
        Add-TestTrackedFile $second 'other/example' 'second'
        Set-TestManifest $second @(@{ source = 'other'; target = 'home'; priority = 2000000 })
        (Get-HomepsickLinkPlan -CastleName second).Conflicts.Count | Should -Be 1
        Enable-HomepsickCastle -CastleName second -Batch
        Enable-HomepsickCastle -CastleName second -Skip -Force
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'first'
        Enable-HomepsickCastle -CastleName second -Force -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'second'
    }

    It 'rejects a file destination that contains another destination' {
        Add-TestTrackedFile $castle 'one/editor'
        Add-TestTrackedFile $castle 'two/settings'
        Set-TestManifest $castle @(@{ source = 'one'; target = 'home' }, @{ source = 'two'; target = 'home'; into = 'editor'; priority = 1 })
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'DestinationOverlap'
        { Enable-HomepsickCastle -CastleName configs -Batch } | Should -Throw '*contains another*'
    }

    It 'never links untracked files from selected roots' {
        Add-TestTrackedFile $castle 'overlay/tracked'
        Set-Content -LiteralPath (Join-Path $castle.CastlePath 'overlay/untracked') -Value 'ignore'
        Set-TestManifest $castle @(@{ source = 'overlay'; target = 'home' })
        (Get-HomepsickLinkPlan -CastleName configs).Winners.RepositoryRelativePath | Should -Be 'overlay/tracked'
    }
}
