# Coverage-guided regressions for read-only rejection of unsafe Git/index and
# filesystem states. Assert preserved data and absent links, not just diagnostics.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psd1') -Force
    $script:previousHome = $env:HOME
    function Set-SafetyManifest {
        # Keep fixture roots explicit so each case controls the destination boundary.
        param([object[]]$Roots, $Destinations = @{})
        @{ version = 1; roots = $Roots; destinations = $Destinations } | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $castle.CastlePath 'homepsick.json')
    }
    function Add-SafetyFile {
        # Seed a real index entry before simulating working-tree damage.
        param([string]$Path)
        $file = Join-Path $castle.CastlePath $Path
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
        Set-Content -LiteralPath $file -Value 'original settings'
        & git -C $castle.CastlePath add -- $Path
        return $file
    }
}
AfterAll { $env:HOME = $script:previousHome }

Describe 'Unsafe source and destination plans' {
    BeforeEach {
        $env:HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $env:HOME | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
        Set-SafetyManifest @()
    }

    It 'rejects a tracked file missing from the working tree without changing its index' {
        $file = Add-SafetyFile 'home/settings'
        $indexBefore = & git -C $castle.CastlePath ls-files --stage
        Remove-Item -LiteralPath $file
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.Errors.Code | Should -Contain 'MissingTrackedSource'
        { Enable-HomepsickCastle -CastleName configs -Batch } | Should -Throw '*MissingTrackedSource*'
        (& git -C $castle.CastlePath ls-files --stage) | Should -Be $indexBefore
        Test-Path -LiteralPath (Join-Path $env:HOME 'settings') | Should -BeFalse
    }

    It 'preserves a directory substituted for an indexed file' {
        $file = Add-SafetyFile 'home/settings'
        Remove-Item -LiteralPath $file
        New-Item -ItemType Directory -Path $file | Out-Null
        $nested = Join-Path $file 'keep'
        Set-Content -LiteralPath $nested -Value 'unrelated data'
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'UnsafeSource'
        { Enable-HomepsickCastle -CastleName configs -Force -Batch } | Should -Throw '*UnsafeSource*'
        Get-Content -LiteralPath $nested | Should -Be 'unrelated data'
    }

    It 'blocks a redirected source parent below a valid root' {
        $file = Add-SafetyFile 'home/nested/settings'
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Move-Item -LiteralPath (Split-Path -Parent $file) -Destination $outside
        New-Item -ItemType SymbolicLink -Path (Split-Path -Parent $file) -Target $outside | Out-Null
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'UnsafeSource'
        { Enable-HomepsickCastle -CastleName configs -Batch } | Should -Throw '*UnsafeSource*'
        Get-Content -LiteralPath (Join-Path $outside 'settings') | Should -Be 'original settings'
        Test-Path -LiteralPath (Join-Path $env:HOME 'nested') | Should -BeFalse
    }

    It 'rejects an unsafe tracked name before resolving a nonexistent source file' {
        # Seed an index-only Windows device name on both hosts, without asking the
        # executing filesystem to create it. Only this fixture disables Git's guard.
        $file = Add-SafetyFile 'payload'
        $blob = (& git -C $castle.CastlePath hash-object -w -- $file).Trim()
        & git -C $castle.CastlePath config core.protectNTFS false
        & git -C $castle.CastlePath update-index --add --cacheinfo "100644,$blob,home/CON"
        $LASTEXITCODE | Should -Be 0
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.Errors.Code | Should -Contain 'UnsafeTrackedPath'
        $plan.Errors.Code | Should -Not -Contain 'MissingTrackedSource'
        { Enable-HomepsickCastle -CastleName configs -Force -Batch } | Should -Throw '*UnsafeTrackedPath*'
        $plan.Winners | Should -BeNullOrEmpty
    }

    It 'reports an applicable foreign-platform destination instead of interpreting it locally' {
        Add-SafetyFile 'home/settings' | Out-Null
        $foreign = if ($IsWindows) { '/foreign/config' } else { 'Q:/foreign/config' }
        Set-SafetyManifest @(@{ source = 'home'; target = 'foreign' }) @{
            foreign = @{ path = $foreign; outsideHome = $true }
        }
        $manifest = Join-Path $castle.CastlePath 'homepsick.json'
        $hash = (Get-FileHash -LiteralPath $manifest).Hash
        (Get-HomepsickLinkPlan -CastleName configs -AllowOutsideHome).Errors.Code | Should -Contain 'InvalidDestination'
        { Enable-HomepsickCastle -CastleName configs -AllowOutsideHome -Batch } | Should -Throw '*another platform*'
        (Get-FileHash -LiteralPath $manifest).Hash | Should -Be $hash
        Test-Path -LiteralPath (Join-Path $env:HOME 'settings') | Should -BeFalse
    }

    It 'retains conservative overlap warnings for foreign destinations skipped on this machine' {
        # Static validation cannot resolve foreign paths. Keep the potential-tie
        # warning without making a harmless inactive-platform mapping invalid.
        $foreign = if ($IsWindows) { '/foreign/config' } else { 'Q:/foreign/config' }
        $foreignOS = if ($IsWindows) { 'linux' } else { 'windows' }
        Set-SafetyManifest @(
            @{ source = 'one'; target = 'foreign'; when = @{ os = $foreignOS } }
            @{ source = 'two'; target = 'foreign'; when = @{ os = $foreignOS } }
        ) @{ foreign = @{ path = $foreign; outsideHome = $true } }
        $nativeOS = if ($IsWindows) { 'windows' } else { 'linux' }
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = $nativeOS }
        $plan.IsValid | Should -BeTrue
        ($plan.Warnings | Where-Object Code -eq PotentialTie).Entries | Should -Be @('roots[0]', 'roots[1]')
        @($plan.Entries | Where-Object { -not $_.Selected }).Count | Should -Be 2
        $plan.Winners | Should -BeNullOrEmpty
    }

    It 'rejects destinations within a repository inspected outside castle storage' {
        # This read-only inspection bypasses the broader storage guard deliberately
        # so the repository-specific source/destination boundary is exercised.
        $repository = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Move-Item -LiteralPath $castle.CastlePath -Destination $repository
        & git -C $repository add homepsick.json
        $file = Join-Path $repository 'home/settings'
        Set-Content -LiteralPath $file -Value 'original settings'
        & git -C $repository add home/settings
        @{
            version = 1
            destinations = @{ inside = @{ path = "$($repository.Replace('\', '/'))/destination"; outsideHome = $true } }
            roots = @(@{ source = 'home'; target = 'inside' })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repository 'homepsick.json')
        $plan = Get-HomepsickLinkPlan -RepositoryPath $repository -AllowOutsideHome
        $plan.Errors.Code | Should -Contain 'SourceDestinationOverlap'
        $plan.IsValid | Should -BeFalse
        Get-Content -LiteralPath $file | Should -Be 'original settings'
        Test-Path -LiteralPath (Join-Path $repository 'destination') | Should -BeFalse
    }
}
