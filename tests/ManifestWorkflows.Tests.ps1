# Integrates clone, pull, submodules, prompts, and external destinations with real
# local Git remotes and links. No fixture depends on a network repository or elevated writes.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psd1') -Force
    $script:previousHome = $env:HOME
    function Set-WorkflowManifest {
        # Rewrite a remote manifest so pulls exercise declaration-only changes as well as file changes.
        param([string]$Repository, [object[]]$Roots, $Destinations = @{})
        @{ version = 1; roots = @($Roots); destinations = $Destinations } | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $Repository 'homepsick.json')
    }
    function Add-WorkflowFile {
        # Create remote content without staging it until the fixture commit boundary.
        param([string]$Repository, [string]$Path, [string]$Value)
        $file = Join-Path $Repository $Path
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($file)) -Force | Out-Null
        Set-Content -LiteralPath $file -Value $Value
    }
    function Commit-WorkflowFiles {
        # Advance the local remote with all fixture changes so pull sees real Git differences.
        param([string]$Repository)
        & git -C $Repository add .
        if ($LASTEXITCODE) { throw 'Failed to stage fixture.' }
        & git -C $Repository commit -m 'Update test castle' | Out-Null
        if ($LASTEXITCODE) { throw 'Failed to commit fixture.' }
    }
    function New-WorkflowSource {
        # Use a local remote with an explicit branch and identity for portable clone/pull tests.
        $source = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        & git init --initial-branch=main $source | Out-Null
        & git -C $source config user.email 'tests@example.invalid'
        & git -C $source config user.name 'Homepsick Tests'
        return $source
    }
    function Invoke-WorkflowPrompt {
        # Use a child console host to exercise ShouldContinue decisions without mocking link behavior.
        param([string]$GitUrl, [string]$Answer)
        $childScript = Join-Path $TestDrive 'interactive-clone.ps1'
        @'
param([string]$ModulePath, [string]$GitUrl)
$ErrorActionPreference = 'Stop'
Import-Module $ModulePath
New-HomepsickCastle -Clone -GitUrl $GitUrl | Out-Null
'@ | Set-Content -LiteralPath $childScript
        $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        $start.UseShellExecute = $false
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in @('-NoProfile', '-File', $childScript, '-ModulePath', (Join-Path $PSScriptRoot '../src/Homepsick.psd1'), '-GitUrl', $GitUrl)) {
            $start.ArgumentList.Add($argument)
        }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        try {
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.StandardInput.WriteLine($Answer)
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(30000)) {
                $process.Kill($true)
                throw 'Interactive fixture timed out.'
            }
            if ($process.ExitCode) { throw $stderr.GetAwaiter().GetResult() }
            return $stdout.GetAwaiter().GetResult()
        }
        finally { $process.Dispose() }
    }
}
AfterAll { $env:HOME = $script:previousHome }

Describe 'Clone and pull with manifests' {
    BeforeEach {
        $env:HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $env:HOME | Out-Null
        $source = New-WorkflowSource
        Add-WorkflowFile $source 'editor/example' 'initial'
        Set-WorkflowManifest $source @(@{ source = 'editor'; target = 'home'; into = '.config/editor' })
        Commit-WorkflowFiles $source
    }

    It 'clones and links selected content without a home directory' {
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Link -Batch
        Test-Path -LiteralPath $castle.CastleSymRoot | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $env:HOME '.config/editor/example') | Should -Be 'initial'
    }

    It 'clones and pulls a mixed Windows and POSIX manifest while foreign destinations stay inactive' {
        # Use a real native absolute destination beneath TestDrive and an absolute
        # literal for the other OS. Neither the foreign drive/path nor its contents
        # should be needed to clone, validate, pull, or link this castle.
        $nativeOS = if ($IsWindows) { 'windows' } else { 'linux' }
        $otherOS = if ($IsWindows) { 'linux' } else { 'windows' }
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $destinations = @{
            nativeConfig = @{ path = $outside; outsideHome = $true }
            otherConfig = @{ path = $(if ($IsWindows) { '/var/lib/homepsick-path-tests/unused' } else { 'Q:\Homepsick Path Tests\unused' }); outsideHome = $true }
        }
        Add-WorkflowFile $source 'other/unused' 'other platform'
        $roots = @(
            @{ source = 'editor'; target = 'nativeConfig'; when = @{ os = $nativeOS } }
            @{ source = 'other'; target = 'otherConfig'; when = @{ os = $otherOS } }
        )
        Set-WorkflowManifest $source $roots $destinations
        Commit-WorkflowFiles $source
        Test-Path -LiteralPath $outside | Should -BeFalse
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Link -Batch -AllowOutsideHome
        Get-Content -LiteralPath (Join-Path $outside 'example') | Should -Be 'initial'
        (Test-HomepsickManifest -CastleName $castle.CastleName).IsValid | Should -BeTrue
        $destinations.otherConfig.path += '/still absent'
        Set-WorkflowManifest $source $roots $destinations
        Add-WorkflowFile $source 'editor/new' 'pulled settings'
        Commit-WorkflowFiles $source
        Update-HomepsickCastle -CastleName $castle.CastleName -Link -Batch -AllowOutsideHome
        $link = Join-Path $outside 'new'
        (Get-Item -LiteralPath $link -Force).LinkType | Should -Be 'SymbolicLink'
        Get-Content -LiteralPath $link | Should -Be 'pulled settings'
        $plan = Get-HomepsickLinkPlan -CastleName $castle.CastleName -AllowOutsideHome
        $plan.IsValid | Should -BeTrue
        $plan.Candidates.RepositoryRelativePath | Should -Not -Contain 'other/unused'
        $plan.Entries | Where-Object Entry -eq 'roots[1]' | Select-Object -ExpandProperty Selected | Should -BeFalse
        $manifest = Get-Content -LiteralPath (Join-Path $castle.CastlePath 'homepsick.json') -Raw | ConvertFrom-Json
        $manifest.destinations.otherConfig.path | Should -BeExactly $destinations.otherConfig.path
    }

    It 'honors <Answer> at the initial clone prompt for a manifest-only castle' -ForEach @(
        @{ Answer = 'Y'; Linked = $true }
        @{ Answer = 'N'; Linked = $false }
    ) {
        # Windows' console host does not redirect prompt text consistently. Verify
        # both decisions through their effects, rather than captured UI formatting.
        Invoke-WorkflowPrompt -GitUrl $source -Answer $Answer | Out-Null
        $link = Join-Path $env:HOME '.config/editor/example'
        Test-Path -LiteralPath $link | Should -Be $Linked
        if ($Linked) {
            (Get-Item -LiteralPath $link -Force).LinkType | Should -Be 'SymbolicLink'
            Get-Content -LiteralPath $link | Should -Be 'initial'
        }
    }

    It 'pulls and links new non-home files' {
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Batch
        Add-WorkflowFile $source 'editor/new' 'new'
        Commit-WorkflowFiles $source
        Update-HomepsickCastle -CastleName $castle.CastleName -Link -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME '.config/editor/new') | Should -Be 'new'
    }

    It 'reselects winners when only the manifest priority changes' {
        Add-WorkflowFile $source 'overlay/example' 'overlay'
        Set-WorkflowManifest $source @(@{ source = 'editor'; target = 'home'; priority = 10 }, @{ source = 'overlay'; target = 'home'; priority = 0 })
        Commit-WorkflowFiles $source
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Link -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'initial'
        Set-WorkflowManifest $source @(@{ source = 'editor'; target = 'home'; priority = 10 }, @{ source = 'overlay'; target = 'home'; priority = 20 })
        Commit-WorkflowFiles $source
        Update-HomepsickCastle -CastleName $castle.CastleName -Link -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'overlay'
    }

    It 'uses the fallback when pull deletes a winning overlay file' {
        Add-WorkflowFile $source 'overlay/example' 'overlay'
        Set-WorkflowManifest $source @(@{ source = 'editor'; target = 'home'; priority = 0 }, @{ source = 'overlay'; target = 'home'; priority = 20 })
        Commit-WorkflowFiles $source
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Link -Batch
        & git -C $source rm overlay/example | Out-Null
        Commit-WorkflowFiles $source
        Update-HomepsickCastle -CastleName $castle.CastleName -Link -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'initial'
    }

    # Mock only the workflow handoff here: real commits and pulls determine whether
    # the caller offers linking for selected changes and ignores skipped-only changes.
    It 'offers the existing link workflow for a selected modification, but not skipped-root changes' {
        Set-WorkflowManifest $source @(
            @{ source = 'editor'; target = 'home' }
            @{ source = 'skipped'; target = 'home'; when = @{ host = 'never-this-test-host.invalid' } }
        )
        Add-WorkflowFile $source 'skipped/example' 'skipped'
        Commit-WorkflowFiles $source
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Batch
        Add-WorkflowFile $source 'editor/example' 'changed'
        Commit-WorkflowFiles $source
        Mock Enable-HomepsickCastle {} -ModuleName Homepsick
        Update-HomepsickCastle -CastleName $castle.CastleName -Link -Batch
        Should -Invoke Enable-HomepsickCastle -ModuleName Homepsick -Times 1 -Exactly
        Add-WorkflowFile $source 'skipped/example' 'also changed'
        Commit-WorkflowFiles $source
        Update-HomepsickCastle -CastleName $castle.CastleName -Link -Batch
        Should -Invoke Enable-HomepsickCastle -ModuleName Homepsick -Times 1 -Exactly
    }

    It 'handles adding a manifest to an ordinary home castle' {
        Remove-Item -LiteralPath (Join-Path $source 'homepsick.json')
        Add-WorkflowFile $source 'home/example' 'home'
        Commit-WorkflowFiles $source
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Link -Batch
        Set-WorkflowManifest $source @(@{ source = 'editor'; target = 'home'; priority = 10 })
        Commit-WorkflowFiles $source
        Update-HomepsickCastle -CastleName $castle.CastleName -Link -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'initial'
    }

    It 'initializes and links tracked files in a non-home submodule' {
        $submodule = New-WorkflowSource
        Add-WorkflowFile $submodule 'settings' 'submodule'
        Commit-WorkflowFiles $submodule
        $previousProtocols = $env:GIT_ALLOW_PROTOCOL
        $env:GIT_ALLOW_PROTOCOL = 'file'
        try {
            & git -C $source submodule add $submodule shared | Out-Null
            Set-WorkflowManifest $source @(@{ source = 'shared'; target = 'home'; into = '.config/shared' })
            Commit-WorkflowFiles $source
            New-HomepsickCastle -Clone -GitUrl $source -Link -Batch | Out-Null
            Get-Content -LiteralPath (Join-Path $env:HOME '.config/shared/settings') | Should -Be 'submodule'
        }
        finally { $env:GIT_ALLOW_PROTOCOL = $previousProtocols }
    }

    It 'does not pull or link when WhatIf is specified' {
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Batch
        Add-WorkflowFile $source 'editor/new' 'new'
        Commit-WorkflowFiles $source
        $before = & git -C $castle.CastlePath rev-parse HEAD
        Update-HomepsickCastle -CastleName $castle.CastleName -Link -Batch -WhatIf
        (& git -C $castle.CastlePath rev-parse HEAD) | Should -Be $before
        Test-Path -LiteralPath (Join-Path $env:HOME '.config/editor/new') | Should -BeFalse
    }
}

# External destinations use a sibling of the synthetic home in TestDrive, so
# opt-in and conflict behavior can be tested without privileged system paths.
Describe 'External destination safeguards' {
    BeforeEach {
        $env:HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $env:HOME | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Add-WorkflowFile $castle.CastlePath 'system/example' 'system'
        & git -C $castle.CastlePath add .
        $destinations = @{ systemConfig = @{ path = $outside.Replace('\', '/'); outsideHome = $true } }
        Set-WorkflowManifest $castle.CastlePath @(@{ source = 'system'; target = 'systemConfig' }) $destinations
    }

    It 'requires runtime opt in while validation and preview remain read only' {
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -BeTrue
        $plan.Winners.Allowed | Should -BeFalse
        $plan.Winners.Reason | Should -BeLike '*AllowOutsideHome*'
        (Test-HomepsickManifest -CastleName configs).IsValid | Should -BeTrue
        Test-Path -LiteralPath $outside | Should -BeFalse
        Enable-HomepsickCastle -CastleName configs -Force -Batch -WarningAction SilentlyContinue
        Test-Path -LiteralPath $outside | Should -BeFalse
        Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -WhatIf
        Test-Path -LiteralPath $outside | Should -BeFalse
        Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -Batch
        Get-Content -LiteralPath (Join-Path $outside 'example') | Should -Be 'system'
    }

    It 'applies the external conflict policy after explicit opt in for a <Kind>' -ForEach @(
        @{ Kind = 'file' }
        @{ Kind = 'directory' }
        @{ Kind = 'unrelated symbolic link' }
        @{ Kind = 'another castle link' }
    ) {
        New-Item -ItemType Directory -Path $outside | Out-Null
        $existingPath = Join-Path $outside 'example'
        switch ($Kind) {
            file { Set-Content -LiteralPath $existingPath -Value 'keep' }
            directory {
                New-Item -ItemType Directory -Path $existingPath | Out-Null
                Set-Content -LiteralPath (Join-Path $existingPath 'keep') -Value 'keep'
            }
            'unrelated symbolic link' {
                $unrelated = Join-Path $outside 'unrelated'
                Set-Content -LiteralPath $unrelated -Value 'keep'
                New-Item -ItemType SymbolicLink -Path $existingPath -Target $unrelated | Out-Null
            }
            'another castle link' {
                $other = New-HomepsickCastle -CastleName other
                Add-WorkflowFile $other.CastlePath 'home/example' 'keep'
                New-Item -ItemType SymbolicLink -Path $existingPath -Target (Join-Path $other.CastleSymRoot 'example') | Out-Null
            }
        }
        $plan = Get-HomepsickLinkPlan -CastleName configs -AllowOutsideHome
        $plan.Conflicts.Count | Should -Be 1
        Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -Batch -WarningAction SilentlyContinue
        $check = if ($Kind -eq 'directory') { Join-Path $existingPath 'keep' } else { $existingPath }
        Get-Content -LiteralPath $check | Should -Be 'keep'
        Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -Force -Batch -WarningAction SilentlyContinue
        $expected = if ($Kind -eq 'directory') { 'keep' } else { 'system' }
        Get-Content -LiteralPath $check | Should -Be $expected
    }

    It 'updates only a verified managed link in an external location' {
        $nativeOS = if ($IsWindows) { 'windows' } else { 'linux' }
        $baseFacts = @{ os = $nativeOS; host = 'base' }
        $overlayFacts = @{ os = $nativeOS; host = 'overlay' }
        Add-WorkflowFile $castle.CastlePath 'overlay/example' 'overlay'
        & git -C $castle.CastlePath add .
        Set-WorkflowManifest $castle.CastlePath @(
            @{ source = 'system'; target = 'systemConfig' }
            @{ source = 'overlay'; target = 'systemConfig'; when = @{ host = 'overlay' } }
        ) $destinations
        Enable-HomepsickCastle -CastleName configs -MachineFacts $baseFacts -AllowOutsideHome -Batch
        (Get-HomepsickLinkPlan -CastleName configs -MachineFacts $overlayFacts -AllowOutsideHome).Winners.ExistingState | Should -Be 'ManagedLink'
        Enable-HomepsickCastle -CastleName configs -MachineFacts $overlayFacts -AllowOutsideHome -Batch -WhatIf
        Get-Content -LiteralPath (Join-Path $outside 'example') | Should -Be 'system'
        Enable-HomepsickCastle -CastleName configs -MachineFacts $overlayFacts -AllowOutsideHome -Batch
        Get-Content -LiteralPath (Join-Path $outside 'example') | Should -Be 'overlay'
        Enable-HomepsickCastle -CastleName configs -MachineFacts $baseFacts -AllowOutsideHome -Batch
        Get-Content -LiteralPath (Join-Path $outside 'example') | Should -Be 'system'
    }

    It 'detects destination aliases even when different target names are used' {
        $destinations.alias = @{ path = $outside.Replace('\', '/'); outsideHome = $true }
        Add-WorkflowFile $castle.CastlePath 'other/example' 'other'
        & git -C $castle.CastlePath add .
        Set-WorkflowManifest $castle.CastlePath @(@{ source = 'system'; target = 'systemConfig' }, @{ source = 'other'; target = 'alias' }) $destinations
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'PriorityTie'
    }

    It 'allows explicitly named home-relative destinations without external opt in' {
        Set-WorkflowManifest $castle.CastlePath @(@{ source = 'system'; target = 'config' }) @{ config = @{ path = '~/.config/example' } }
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.Winners.Allowed | Should -BeTrue
        $plan.Winners.OutsideHome | Should -BeFalse
        Enable-HomepsickCastle -CastleName configs -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME '.config/example/example') | Should -Be 'system'
    }

    It 'allows absolute destinations inside home without external declarations or opt in' {
        $inside = (Join-Path $env:HOME '.config/example').Replace('\', '/')
        Set-WorkflowManifest $castle.CastlePath @(@{ source = 'system'; target = 'config' }) @{ config = @{ path = $inside } }
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -BeTrue
        $plan.Winners.Allowed | Should -BeTrue
        $plan.Winners.OutsideHome | Should -BeFalse
    }

    It 'forwards external opt in through clone and pull' {
        $source = New-WorkflowSource
        Add-WorkflowFile $source 'system/example' 'cloned'
        Set-WorkflowManifest $source @(@{ source = 'system'; target = 'systemConfig' }) $destinations
        Commit-WorkflowFiles $source
        $clone = New-HomepsickCastle -Clone -GitUrl $source -Link -Batch -AllowOutsideHome
        Get-Content -LiteralPath (Join-Path $outside 'example') | Should -Be 'cloned'
        Add-WorkflowFile $source 'system/added' 'pulled'
        Commit-WorkflowFiles $source
        Update-HomepsickCastle -CastleName $clone.CastleName -Link -Batch -AllowOutsideHome
        Get-Content -LiteralPath (Join-Path $outside 'added') | Should -Be 'pulled'
    }
}
