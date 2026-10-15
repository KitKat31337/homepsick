# Regressions for review findings: consistent conflict switches, diagnostics,
# stale-link retention, and discoverable public help. External paths stay in TestDrive.
# Compare the same conflict matrix inside and outside home. Directory-link target
# contents are asserted separately so removing one link cannot mask recursive deletion.
BeforeDiscovery {
    $conflictCases = foreach ($location in @('home', 'external')) {
        foreach ($kind in @('file', 'file symlink', 'directory symlink', 'directory')) {
            foreach ($mode in @(
                @{ Name = 'Batch'; Options = @{ Batch = $true }; Replace = $false }
                @{ Name = 'Skip'; Options = @{ Skip = $true }; Replace = $false }
                @{ Name = 'Force'; Options = @{ Force = $true }; Replace = $true }
                @{ Name = 'Force Batch'; Options = @{ Force = $true; Batch = $true }; Replace = $true }
                @{ Name = 'Force Skip'; Options = @{ Force = $true; Skip = $true }; Replace = $false }
                @{ Name = 'Force WhatIf'; Options = @{ Force = $true; WhatIf = $true }; Replace = $false }
            )) {
                @{ Location = $location; Kind = $kind; Mode = $mode.Name; Options = $mode.Options; Replace = ($mode.Replace -and $kind -ne 'directory') }
            }
        }
    }
}
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psd1') -Force
    $script:previousHome = $env:HOME
    function Set-ReviewManifest {
        # Make competing mappings and opt-in declarations explicit for each regression.
        param([object[]]$Roots, $Destinations = @{})
        @{ version = 1; roots = $Roots; destinations = $Destinations } | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $castle.CastlePath 'homepsick.json')
    }
    function Add-ReviewFile {
        # Stage source files so conflict fixtures exercise actual link winners.
        param([string]$Path, [string]$Value = 'castle settings')
        $source = Join-Path $castle.CastlePath $Path
        New-Item -ItemType Directory -Path (Split-Path -Parent $source) -Force | Out-Null
        Set-Content -LiteralPath $source -Value $Value
        & git -C $castle.CastlePath add -- $Path
    }
}
AfterAll { $env:HOME = $script:previousHome }

Describe 'Consistent and safe destination conflicts' {
    BeforeEach {
        $env:HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $env:HOME | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
        Add-ReviewFile 'overlay/example'
    }

    It 'honors <Mode> for a <Kind> conflict at <Location>' -ForEach $conflictCases {
        $destination = if ($Location -eq 'home') { Join-Path $env:HOME 'configured' } else { Join-Path $TestDrive ([guid]::NewGuid().ToString()) }
        $target = if ($Location -eq 'home') { 'home' } else { 'external' }
        $into = if ($Location -eq 'home') { 'configured' } else { $null }
        Set-ReviewManifest @(@{ source = 'overlay'; target = $target; priority = 100; into = $(if ($into) { $into } else { 'files' }) }) @{
            external = @{ path = $destination.Replace('\', '/'); outsideHome = $true }
        }
        if ($Location -eq 'external') { $destination = Join-Path $destination 'files' }
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $link = Join-Path $destination 'example'
        $unrelated = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        switch ($Kind) {
            file { Set-Content -LiteralPath $link -Value 'keep' }
            'file symlink' {
                Set-Content -LiteralPath $unrelated -Value 'keep'
                New-Item -ItemType SymbolicLink -Path $link -Target $unrelated | Out-Null
            }
            'directory symlink' {
                New-Item -ItemType Directory -Path $unrelated | Out-Null
                Set-Content -LiteralPath (Join-Path $unrelated 'keep') -Value 'keep'
                New-Item -ItemType SymbolicLink -Path $link -Target $unrelated | Out-Null
            }
            directory {
                New-Item -ItemType Directory -Path $link | Out-Null
                Set-Content -LiteralPath (Join-Path $link 'keep') -Value 'keep'
                Set-Content -LiteralPath (Join-Path $link '.hidden') -Value 'keep hidden'
            }
        }
        $plan = Get-HomepsickLinkPlan -CastleName configs -AllowOutsideHome
        $plan.Conflicts.Count | Should -Be 1
        if ($Kind -eq 'directory') { $plan.Conflicts.Reason | Should -BeLike '*directory trees are never replaced*' }
        Enable-HomepsickCastle -CastleName configs -AllowOutsideHome @Options -WarningAction SilentlyContinue
        if ($Replace) {
            (Get-Item -LiteralPath $link -Force).LinkType | Should -Be 'SymbolicLink'
            Get-Content -LiteralPath $link | Should -Be 'castle settings'
        }
        else {
            $check = if ($Kind -in @('directory', 'directory symlink')) { Join-Path $link 'keep' } else { $link }
            Get-Content -LiteralPath $check | Should -Be 'keep'
        }
        if ($Kind -eq 'file symlink') { Get-Content -LiteralPath $unrelated | Should -Be 'keep' }
        if ($Kind -eq 'directory symlink') { Get-Content -LiteralPath (Join-Path $unrelated 'keep') | Should -Be 'keep' }
        if ($Kind -eq 'directory') { Get-Content -LiteralPath (Join-Path $link '.hidden') | Should -Be 'keep hidden' }
        Get-Content -LiteralPath (Join-Path $castle.CastlePath 'overlay/example') | Should -Be 'castle settings'
    }

    It 'also protects unrelated directory trees in a castle without a manifest' {
        Add-ReviewFile 'home/example'
        $link = Join-Path $env:HOME 'example'
        New-Item -ItemType Directory -Path $link | Out-Null
        Set-Content -LiteralPath (Join-Path $link 'keep') -Value 'keep'
        Enable-HomepsickCastle -CastleName configs -Force -Batch -WarningAction SilentlyContinue
        Get-Content -LiteralPath (Join-Path $link 'keep') | Should -Be 'keep'
    }
}

Describe 'Review validation, diagnostics, and help' {
    BeforeEach {
        $env:HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $env:HOME | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
    }

    It 'rejects identical empty declarations, treating scalar and singleton conditions alike' {
        New-Item -ItemType Directory -Path (Join-Path $castle.CastlePath 'empty') | Out-Null
        Set-ReviewManifest @(
            @{ source = 'empty'; target = 'home'; when = @{ os = 'linux' } }
            @{ source = 'empty'; target = 'home'; when = @{ os = @('linux') }; priority = 100 }
        )
        $validation = Test-HomepsickManifest -CastleName configs
        $validation.IsValid | Should -BeFalse
        ($validation.Errors | Where-Object Code -eq DuplicateRoot).Entries | Should -Be @('roots[0]', 'roots[1]')
        { Enable-HomepsickCastle -CastleName configs -Batch } | Should -Throw '*DuplicateRoot*roots`[0`]*roots`[1`]*'
    }

    It 'compares duplicate condition arrays independently of property and value order' {
        Set-ReviewManifest @(
            @{ source = 'empty'; target = 'home'; when = @{ windowsRelease = @('10', '11'); windowsEdition = 'pro' } }
            @{ source = 'empty'; target = 'home'; when = @{ windowsEdition = 'pro'; windowsRelease = @('11', '10') } }
        )
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'DuplicateRoot'
    }

    It 'warns about existing sources with only untracked files, including skipped roots' {
        $source = Join-Path $castle.CastlePath 'empty'
        New-Item -ItemType Directory -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'untracked') -Value 'untracked'
        Set-ReviewManifest @(@{ source = 'empty'; target = 'home'; when = @{ os = 'windows' } })
        $validation = Test-HomepsickManifest -CastleName configs -MachineFacts @{ os = 'linux' }
        $validation.IsValid | Should -BeTrue
        ($validation.Warnings | Where-Object Code -eq NoTrackedFiles).Entries | Should -Be @('roots[0]')
        (Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'linux' }).Warnings.Code | Should -Contain 'NoTrackedFiles'
    }

    It 'retains valid mutually exclusive shared-source entries' {
        New-Item -ItemType Directory -Path (Join-Path $castle.CastlePath 'editor') | Out-Null
        Set-ReviewManifest @(
            @{ source = 'editor'; target = 'home'; when = @{ os = 'windows' } }
            @{ source = 'editor'; target = 'home'; when = @{ os = 'linux' } }
        )
        $validation = Test-HomepsickManifest -CastleName configs
        $validation.IsValid | Should -BeTrue
        $validation.Errors | Should -BeNullOrEmpty
    }

    It 'warns about an always-shadowed entry with the correct identifier in either order' -ForEach @(
        @{ Reverse = $false; ShadowedEntry = 'roots[1]' }
        @{ Reverse = $true; ShadowedEntry = 'roots[0]' }
    ) {
        # Reusing one source is legal, but an unconditional higher priority can
        # make its conditional declaration unreachable regardless of file contents.
        $roots = @(
            @{ source = 'overlay'; target = 'home'; priority = 1000 }
            @{ source = 'overlay'; target = 'home'; priority = 1; when = @{ os = 'linux' } }
        )
        if ($Reverse) { [array]::Reverse($roots) }
        Set-ReviewManifest $roots
        Add-ReviewFile 'overlay/example'
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'linux' }
        $plan.IsValid | Should -BeTrue
        ($plan.Warnings | Where-Object Code -eq ShadowedEntry).Entries | Should -Be $ShadowedEntry
        $plan.Shadowed.Entry | Should -Be $ShadowedEntry
        $plan.Winners.Priority | Should -Be 1000
    }

    It 'exposes internal result type metadata without requiring public type accelerators' {
        Set-ReviewManifest @()
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $validation = Test-HomepsickManifest -CastleName configs
        (Get-Command Get-HomepsickLinkPlan).OutputType.Name | Should -Contain $plan.GetType().Name
        (Get-Command Test-HomepsickManifest).OutputType.Name | Should -Contain $validation.GetType().Name
        $plan.Errors.GetType().GetElementType().Name | Should -Be 'HomepsickDiagnostic'
        $plan.Entries.GetType().GetElementType().Name | Should -Be 'HomepsickRootSelection'
    }

    It 'retains potential-overlap warnings in preview without repeating them while linking' {
        Add-ReviewFile 'release/example'
        Add-ReviewFile 'edition/example'
        Add-ReviewFile 'combined/example'
        Set-ReviewManifest @(
            @{ source = 'release'; target = 'home'; when = @{ windowsRelease = '11' } }
            @{ source = 'edition'; target = 'home'; when = @{ windowsEdition = 'pro' } }
            @{ source = 'combined'; target = 'home'; when = @{ windowsRelease = '11'; windowsEdition = 'pro' } }
        )
        $facts = @{ os = 'windows'; windowsRelease = '11'; windowsEdition = 'pro' }
        (Get-HomepsickLinkPlan -CastleName configs -MachineFacts $facts).Warnings.Code | Should -Contain 'PotentialTie'
        (Test-HomepsickManifest -CastleName configs -MachineFacts $facts).Warnings.Code | Should -Contain 'PotentialTie'
        Enable-HomepsickCastle -CastleName configs -MachineFacts $facts -Batch -WarningVariable linkWarnings
        @($linkWarnings).Count | Should -Be 0
    }

    It 'includes codes and entry identifiers for actual tie errors' {
        Add-ReviewFile 'one/example'
        Add-ReviewFile 'two/example'
        Set-ReviewManifest @(@{ source = 'one'; target = 'home' }, @{ source = 'two'; target = 'home' })
        { Enable-HomepsickCastle -CastleName configs -Force } | Should -Throw '*PriorityTie*roots`[0`]*roots`[1`]*'
    }

    It 'keeps stale links when <Change> stops mapping them without a replacement' -ForEach @(
        @{ Change = 'a condition'; Condition = $true }
        @{ Change = 'a destination mapping'; Condition = $false }
    ) {
        Add-ReviewFile 'overlay/example'
        Set-ReviewManifest @(@{ source = 'overlay'; target = 'home'; into = 'old'; when = @{ os = 'linux' } })
        Enable-HomepsickCastle -CastleName configs -MachineFacts @{ os = 'linux' } -Batch
        $stale = Join-Path $env:HOME 'old/example'
        if ($Condition) {
            Enable-HomepsickCastle -CastleName configs -MachineFacts @{ os = 'windows' } -Batch -Force
        }
        else {
            Set-ReviewManifest @(@{ source = 'overlay'; target = 'home'; into = 'new'; when = @{ os = 'linux' } })
            Enable-HomepsickCastle -CastleName configs -MachineFacts @{ os = 'linux' } -Batch -Force
        }
        (Get-Item -LiteralPath $stale -Force).LinkType | Should -Be 'SymbolicLink'
        Get-Content -LiteralPath $stale | Should -Be 'castle settings'
    }

    It 'provides parameter help and examples for <Command>' -ForEach @(
        @{ Command = 'Test-HomepsickManifest'; Parameters = @('CastleName', 'RepositoryPath', 'MachineFacts') }
        @{ Command = 'Get-HomepsickLinkPlan'; Parameters = @('CastleName', 'RepositoryPath', 'MachineFacts', 'AllowOutsideHome') }
        @{ Command = 'Add-HomepsickFile'; Parameters = @('CastleName', 'Path', 'Root', 'AllowOutsideHome', 'MachineFacts') }
        @{ Command = 'Enable-HomepsickCastle'; Parameters = @('CastleName', 'All', 'Force', 'Skip', 'Batch', 'AllowOutsideHome', 'MachineFacts') }
        @{ Command = 'New-HomepsickCastle'; Parameters = @('Clone', 'GitUrl', 'CastleName', 'Link', 'Batch', 'AllowOutsideHome') }
        @{ Command = 'Invoke-HomepsickCastleRefresh'; Parameters = @('CastleName', 'All', 'Days', 'Pull', 'Batch', 'Link', 'AllowOutsideHome') }
        @{ Command = 'Update-HomepsickCastle'; Parameters = @('CastleName', 'All', 'Link', 'Batch', 'AllowOutsideHome') }
        @{ Command = 'Get-HomepsickCastle'; Parameters = @('CastleName') }
        @{ Command = 'Enter-HomepsickCastle'; Parameters = @('CastleName') }
        @{ Command = 'Get-HomepsickCastleStatus'; Parameters = @('CastleName', 'All') }
    ) {
        $help = Get-Help $Command -Full
        @($help.examples.example).Count | Should -BeGreaterThan 0
        foreach ($parameter in $Parameters) {
            ($help.parameters.parameter | Where-Object name -eq $parameter).description.Text | Should -Not -BeNullOrEmpty
        }
    }
}
