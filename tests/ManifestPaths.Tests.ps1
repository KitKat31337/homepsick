# Exercises Windows and POSIX manifest literals on both CI hosts. Synthetic facts
# select either platform, while actual writes stay beneath TestDrive on the native
# filesystem. Foreign destinations are data, never directories to create locally.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psd1') -Force
    $script:previousHome = $env:HOME
    function Set-PathManifest {
        # Serialize path literals as JSON data, including correctly escaped backslashes.
        param([object[]]$Roots = @(), $Destinations = @{})
        @{ version = 1; roots = $Roots; destinations = $Destinations } | ConvertTo-Json -Depth 12 |
            Set-Content -LiteralPath (Join-Path $castle.CastlePath 'homepsick.json')
    }
    function Add-PathSource {
        # Only indexed files should contribute candidates for the platform mappings.
        param([string]$Path, [string]$Value = 'source settings')
        $file = Join-Path $castle.CastlePath $Path
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
        Set-Content -LiteralPath $file -Value $Value
        & git -C $castle.CastlePath add -- $Path
        if ($LASTEXITCODE) { throw 'Failed to stage path fixture.' }
    }
}
AfterAll { $env:HOME = $script:previousHome }

Describe 'Portable manifest destination declarations' {
    BeforeEach {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $env:HOME = Join-Path $fixture 'home with spaces'
        New-Item -ItemType Directory -Path $env:HOME -Force | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
        Remove-Item -LiteralPath $castle.CastleSymRoot
    }

    It 'accepts unused <Label> as literal data without requiring that destination to exist' -ForEach @(
        @{ Label = 'Windows drive path'; Literal = 'C:/ProgramData/Homepsick Path Tests/config' }
        @{ Label = 'Windows backslash path'; Literal = 'C:\ProgramData\Homepsick Path Tests\config' }
        @{ Label = 'alternate backslash drive'; Literal = 'd:\Config Files\Editor' }
        @{ Label = 'mixed Windows separators'; Literal = 'D:\Config Files/Editor\settings' }
        @{ Label = 'lowercase alternate drive and spaces'; Literal = 'z:/Config Files/Homepsick Path Tests' }
        @{ Label = 'POSIX absolute path'; Literal = '/var/lib/homepsick path tests/config' }
        @{ Label = 'portable home path'; Literal = '~/AppData/Roaming/Editor' }
        @{ Label = 'PowerShell-looking directory name'; Literal = 'C:/Config Files/$(throw path-data)/Editor' }
    ) {
        Set-PathManifest -Destinations @{ unused = @{ path = $Literal; outsideHome = $true } }
        $manifest = Join-Path $castle.CastlePath 'homepsick.json'
        $hash = (Get-FileHash -LiteralPath $manifest).Hash
        (Test-HomepsickManifest -CastleName configs).IsValid | Should -BeTrue
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.IsValid | Should -BeTrue
        $plan.Candidates | Should -BeNullOrEmpty
        Enable-HomepsickCastle -CastleName configs -Batch
        (Get-FileHash -LiteralPath $manifest).Hash | Should -Be $hash
        (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).destinations.unused.path | Should -BeExactly $Literal
        @(Get-ChildItem -LiteralPath $env:HOME -Force).Name | Should -Be @('.homesick')
    }

    It 'rejects <Label> consistently even in an unused destination declaration' -ForEach @(
        @{ Label = 'UNC backslashes'; Literal = '\\server\share\Editor' }
        @{ Label = 'UNC forward slashes'; Literal = '//server/share/Editor' }
        @{ Label = 'Windows device prefix'; Literal = '\\?\C:\Editor' }
        @{ Label = 'drive-relative path'; Literal = 'C:Editor/settings' }
        @{ Label = 'current-drive-relative path'; Literal = '\Editor\settings' }
        @{ Label = 'drive root'; Literal = 'C:/' }
        @{ Label = 'backslash drive root'; Literal = 'D:\' }
        @{ Label = 'Windows traversal'; Literal = 'C:/config/../escape' }
        @{ Label = 'backslash Windows traversal'; Literal = 'C:\config\..\escape' }
        @{ Label = 'POSIX traversal'; Literal = '/var/config/../escape' }
        @{ Label = 'empty Windows path component'; Literal = 'C:/config//settings' }
        @{ Label = 'reserved Windows device'; Literal = 'C:/config/CON' }
        @{ Label = 'trailing Windows dot'; Literal = 'C:/config./settings' }
        @{ Label = 'NTFS alternate stream'; Literal = 'C:/config/settings:stream' }
    ) {
        Set-PathManifest -Destinations @{ unused = @{ path = $Literal; outsideHome = $true } }
        $manifest = Join-Path $castle.CastlePath 'homepsick.json'
        $hash = (Get-FileHash -LiteralPath $manifest).Hash
        $result = Test-HomepsickManifest -CastleName configs
        $result.IsValid | Should -BeFalse
        $result.Errors.Code | Should -Contain 'InvalidDestinationPath'
        $result.Errors.Code | Should -Not -Contain 'InvalidJson'
        (Get-FileHash -LiteralPath $manifest).Hash | Should -Be $hash
    }

    It 'requires outsideHome for unused absolute <Literal> on either platform' -ForEach @(
        @{ Literal = 'C:/ProgramData/Homepsick Path Tests' }
        @{ Literal = 'D:\Config Files\Homepsick Path Tests' }
        @{ Literal = '/var/lib/homepsick-path-tests' }
    ) {
        Set-PathManifest -Destinations @{ unused = @{ path = $Literal } }
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'OutsideHomeDeclaration'
    }

    It 'rejects <Field> using <Literal> even when its root is inactive' -ForEach @(
        @{ Field = 'source'; Literal = 'C:/Editor'; Code = 'InvalidSource' }
        @{ Field = 'source'; Literal = 'Editor\settings'; Code = 'InvalidSource' }
        @{ Field = 'into'; Literal = 'C:/Editor'; Code = 'InvalidInto' }
        @{ Field = 'into'; Literal = 'Editor\settings'; Code = 'InvalidInto' }
    ) {
        $root = @{ source = 'shared'; target = 'home'; when = @{ os = 'windows' } }
        $root[$Field] = $Literal
        Set-PathManifest -Roots @($root)
        $result = Test-HomepsickManifest -CastleName configs -MachineFacts @{ os = 'linux' }
        $result.IsValid | Should -BeFalse
        $result.Errors.Code | Should -Contain $Code
    }
}

Describe 'Mixed Windows and Linux manifest paths' {
    BeforeEach {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $env:HOME = Join-Path $fixture 'home with spaces'
        New-Item -ItemType Directory -Path $env:HOME -Force | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
        Remove-Item -LiteralPath $castle.CastleSymRoot
        $nativeOS = if ($IsWindows) { 'windows' } else { 'linux' }
        $nativeDestination = Join-Path $fixture 'native destination with spaces'
        $nativeLiteral = $nativeDestination.Replace('\', '/')
        # On Windows exercise lowercase drive spelling as well as literal slashes.
        # On Linux never ask the filesystem to create a Windows-looking directory.
        if ($IsWindows) { $nativeLiteral = $nativeLiteral.Substring(0, 1).ToLowerInvariant() + $nativeLiteral.Substring(1) }
        $foreignLiteral = if ($IsWindows) { '/var/lib/homepsick-path-tests/config' } else { 'Q:/Homepsick Path Tests/config' }
    }

    It 'skips an unconditional <Literal> on Linux with source exists = <SourceExists>' -ForEach @(
        @{ SourceExists = $false; Literal = 'Q:/Homepsick Path Tests/config' }
        @{ SourceExists = $true; Literal = 'Q:/Homepsick Path Tests/config' }
        @{ SourceExists = $false; Literal = 'q:\Homepsick Path Tests\config' }
        @{ SourceExists = $true; Literal = 'q:\Homepsick Path Tests\config' }
    ) {
        Add-PathSource 'shared/settings.json'
        if ($SourceExists) { Add-PathSource 'other/unused.json' }
        Set-PathManifest -Roots @(
            @{ source = 'shared'; target = 'home'; into = '.config/editor' }
            @{ source = 'other'; target = 'otherConfig' }
        ) -Destinations @{ otherConfig = @{ path = $Literal; outsideHome = $true } }
        $manifest = Join-Path $castle.CastlePath 'homepsick.json'
        $hash = (Get-FileHash -LiteralPath $manifest).Hash
        $indexBefore = (& git -C $castle.CastlePath ls-files --stage) -join "`n"
        $facts = @{ os = 'linux' }
        (Test-HomepsickManifest -CastleName configs -MachineFacts $facts).IsValid | Should -BeTrue
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts $facts
        $plan.IsValid | Should -BeTrue
        $plan.Winners.Count | Should -Be 1
        $plan.Candidates.Entry | Should -Be 'roots[0]'
        ($plan.Entries | Where-Object Entry -eq 'roots[1]').Selected | Should -BeFalse
        ($plan.Entries | Where-Object Entry -eq 'roots[1]').Reasons -join ' ' | Should -BeLike '*requires OS*windows*'
        ($plan.Entries | Where-Object Entry -eq 'roots[1]').CalculatedPriority | Should -Be 0
        @($plan.Warnings | Where-Object Code -eq MissingSource).Count | Should -Be $(if ($SourceExists) { 0 } else { 1 })
        # An inactive external destination must not need runtime opt-in or prevent
        # ordinary home links, even when its source was omitted from this checkout.
        Enable-HomepsickCastle -CastleName configs -MachineFacts $facts -Batch -WarningAction SilentlyContinue
        $link = Join-Path $env:HOME '.config/editor/settings.json'
        (Get-Item -LiteralPath $link -Force).LinkType | Should -Be 'SymbolicLink'
        Get-Content -LiteralPath $link | Should -Be 'source settings'
        (Get-FileHash -LiteralPath $manifest).Hash | Should -Be $hash
        ((& git -C $castle.CastlePath ls-files --stage) -join "`n") | Should -Be $indexBefore
    }

    It 'rejects a Windows destination with contradictory <Label> conditions' -ForEach @(
        @{ Label = 'explicit Linux'; When = @{ os = 'linux' } }
        @{ Label = 'Linux distribution'; When = @{ distro = 'ubuntu' } }
        @{ Label = 'Linux lineage'; When = @{ distroLike = 'debian' } }
    ) {
        Set-PathManifest -Roots @(@{ source = 'missing'; target = 'windowsConfig'; when = $When }) -Destinations @{
            windowsConfig = @{ path = 'D:\Config Files\Editor'; outsideHome = $true }
        }
        $result = Test-HomepsickManifest -CastleName configs
        $result.IsValid | Should -BeFalse
        ($result.Errors | Where-Object Code -eq UnreachableEntry).Entries | Should -Be 'roots[0]'
        ($result.Errors | Where-Object Code -eq UnreachableEntry).Message | Should -BeLike '*destination*incompatible operating systems*'
    }

    It 'does not add inferred OS points to <Label>' -ForEach @(
        @{ Label = 'unconditional entry'; When = @{}; Score = 0 }
        @{ Label = 'explicit Windows'; When = @{ os = 'windows' }; Score = 100 }
        @{ Label = 'OS array including Windows'; When = @{ os = @('windows', 'linux') }; Score = 50 }
        @{ Label = 'host condition'; When = @{ host = 'path-ci' }; Score = 100000 }
    ) {
        Set-PathManifest -Roots @(@{ source = 'missing'; target = 'windowsConfig'; when = $When }) -Destinations @{
            windowsConfig = @{ path = 'D:\Config Files\Editor'; outsideHome = $true }
        }
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'windows'; host = 'path-ci' }
        $plan.Entries[0].Selected | Should -BeTrue
        $plan.Entries[0].DestinationOS | Should -Be @('windows')
        $plan.Entries[0].Priority | Should -Be $Score
        $plan.Entries[0].CalculatedPriority | Should -Be $Score
        $linux = Get-HomepsickLinkPlan -CastleName configs -MachineFacts @{ os = 'linux'; host = 'path-ci' }
        $linux.IsValid | Should -BeTrue
        $linux.Entries[0].Selected | Should -BeFalse
        $linux.Entries[0].CalculatedPriority | Should -Be $Score
    }

    It 'keeps backslashes invalid in tracked relative filenames on both hosts' {
        # A backslash can be a literal Git filename on Linux but a separator on
        # Windows. Inject the same index record at the Git process boundary so
        # neither host's filesystem silently changes the malformed relative name.
        Add-PathSource 'shared/payload'
        $blob = (& git -C $castle.CastlePath hash-object -- shared/payload).Trim()
        $script:unsafePathIndex = "100644 $blob 0`tshared/bad\name`0"
        Mock Invoke-HomepsickGit {
            [pscustomobject]@{ ExitCode = 0; Output = $script:unsafePathIndex; Error = '' }
        } -ModuleName Homepsick -ParameterFilter { $Arguments[0] -eq 'ls-files' }
        Set-PathManifest -Roots @(@{ source = 'shared'; target = 'home' })
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.Errors.Code | Should -Contain 'UnsafeTrackedPath'
        { Enable-HomepsickCastle -CastleName configs -Batch } | Should -Throw '*UnsafeTrackedPath*'
        Test-Path -LiteralPath (Join-Path $env:HOME 'bad') | Should -BeFalse
    }

    # Both contexts run on both CI hosts. Facts select conditions only; they cannot
    # make another OS's absolute-path syntax meaningful on the executing filesystem.
    It 'resolves shared settings under <OS> facts with Windows backslashes = <Backslashes>' -ForEach @(
        @{ OS = 'windows'; Backslashes = $false; Facts = @{ os = 'windows'; windowsRelease = '11'; windowsEdition = 'pro' }; Target = 'windowsConfig'; Entry = 'roots[0]' }
        @{ OS = 'windows'; Backslashes = $true; Facts = @{ os = 'windows'; windowsRelease = '11'; windowsEdition = 'pro' }; Target = 'windowsConfig'; Entry = 'roots[0]' }
        @{ OS = 'linux'; Backslashes = $false; Facts = @{ os = 'linux'; distro = 'ubuntu'; distroVersion = '24.04' }; Target = 'linuxConfig'; Entry = 'roots[1]' }
    ) {
        Add-PathSource 'shared/settings.json'
        Add-PathSource 'fallback/ordinary.txt' 'home fallback'
        $destinations = @{
            windowsConfig = @{ path = $(if ($IsWindows) { $nativeLiteral } else { $foreignLiteral }); outsideHome = $true }
            linuxConfig = @{ path = $(if ($IsWindows) { $foreignLiteral } else { $nativeLiteral }); outsideHome = $true }
        }
        if ($Backslashes) { $destinations.windowsConfig.path = $destinations.windowsConfig.path.Replace('/', '\') }
        $roots = @(
            @{ source = 'shared'; target = 'windowsConfig'; into = 'nested settings' }
            @{ source = 'shared'; target = 'linuxConfig'; into = 'nested settings'; when = @{ distro = 'ubuntu'; distroVersion = '24.04' } }
            @{ source = 'fallback'; target = 'home' }
        )
        Set-PathManifest -Roots $roots -Destinations $destinations
        $manifest = Join-Path $castle.CastlePath 'homepsick.json'
        $hash = (Get-FileHash -LiteralPath $manifest).Hash
        $indexBefore = (& git -C $castle.CastlePath ls-files --stage) -join "`n"
        $plan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts $Facts
        $isNative = $OS -eq $nativeOS
        $plan.IsValid | Should -Be $isNative
        (Test-HomepsickManifest -CastleName configs -MachineFacts $Facts).IsValid | Should -Be $isNative
        ($plan.Entries | Where-Object Entry -eq $Entry).Selected | Should -BeTrue
        @($plan.Entries | Where-Object { $_.Source -eq 'shared' -and $_.Selected }).Count | Should -Be 1
        Test-Path -LiteralPath $nativeDestination | Should -BeFalse
        if (-not $isNative) {
            $plan.Errors.Code | Should -Contain 'InvalidDestination'
            ($plan.Errors | Where-Object Code -eq InvalidDestination).Entries | Should -Be $Entry
            { Enable-HomepsickCastle -CastleName configs -MachineFacts $Facts -AllowOutsideHome -Force -Batch } |
                Should -Throw '*InvalidDestination*another platform*'
            # Preflight must reject the whole plan before even the valid fallback
            # can create a link; opt-in and Force cannot authorize foreign syntax.
            Test-Path -LiteralPath (Join-Path $env:HOME 'ordinary.txt') | Should -BeFalse
            ((& git -C $castle.CastlePath ls-files --stage) -join "`n") | Should -Be $indexBefore
        }
        else {
            $file = @($plan.Winners | Where-Object Target -eq $Target)
            $expected = [IO.Path]::GetFullPath([IO.Path]::Combine($destinations[$Target].path, 'nested settings', 'settings.json'))
            $file.Count | Should -Be 1
            $file[0].DestinationPath | Should -Be $expected
            $file[0].ExistingState | Should -Be 'Missing'
            $file[0].Allowed | Should -BeFalse
            Enable-HomepsickCastle -CastleName configs -MachineFacts $Facts -Batch -WarningAction SilentlyContinue
            Get-Content -LiteralPath (Join-Path $env:HOME 'ordinary.txt') | Should -Be 'home fallback'
            Test-Path -LiteralPath $nativeDestination | Should -BeFalse
            Enable-HomepsickCastle -CastleName configs -MachineFacts $Facts -AllowOutsideHome -WhatIf
            Test-Path -LiteralPath $nativeDestination | Should -BeFalse
            Enable-HomepsickCastle -CastleName configs -MachineFacts $Facts -AllowOutsideHome -Batch
            (Get-Item -LiteralPath $expected -Force).LinkType | Should -Be 'SymbolicLink'
            Get-Content -LiteralPath $expected | Should -Be 'source settings'
            (Get-FileHash -LiteralPath $manifest).Hash | Should -Be $hash
            if ($IsWindows) {
                # Reauthor only the separators. Existing links must retain the same
                # destination and AlreadyLinked state, with no replacement conflict.
                $destinations.windowsConfig.path = if ($Backslashes) {
                    $destinations.windowsConfig.path.Replace('\', '/')
                } else { $destinations.windowsConfig.path.Replace('/', '\') }
                Set-PathManifest -Roots $roots -Destinations $destinations
                $hash = (Get-FileHash -LiteralPath $manifest).Hash
                $equivalentPlan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts $Facts -AllowOutsideHome
                $sameFile = $equivalentPlan.Winners | Where-Object Target -eq windowsConfig
                $sameFile.DestinationPath | Should -Be $expected
                $sameFile.ExistingState | Should -Be 'AlreadyLinked'
                $equivalentPlan.Conflicts | Should -BeNullOrEmpty
            }
            $tracked = Join-Path (Split-Path -Parent $expected) 'tracked.json'
            Set-Content -LiteralPath $tracked -Value 'new native settings'
            Add-HomepsickFile -CastleName configs -Path $tracked -Root $Entry -MachineFacts $Facts -AllowOutsideHome
            (& git -C $castle.CastlePath ls-files) | Should -Contain 'shared/tracked.json'
            Get-Content -LiteralPath (Join-Path $castle.CastlePath 'shared/tracked.json') | Should -Be 'new native settings'
            (Get-Item -LiteralPath $tracked -Force).LinkType | Should -Be 'SymbolicLink'
            $linkedPlan = Get-HomepsickLinkPlan -CastleName configs -MachineFacts $Facts -AllowOutsideHome
            $linkedPlan.IsValid | Should -BeTrue
            $linkedPlan.Winners.ExistingState | Should -Not -Contain 'Missing'
            $linkedPlan.Candidates | Where-Object Entry -ne $Entry | Where-Object Target -ne home | Should -BeNullOrEmpty
        }
        (Get-FileHash -LiteralPath $manifest).Hash | Should -Be $hash
    }
}
