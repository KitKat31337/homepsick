# Exercises schema diagnostics and filesystem boundaries through read-only public
# validation/preview, checking that rejected input never changes source or destination data.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psd1') -Force
    $script:previousHome = $env:HOME
    function Write-ValidationManifest {
        # Keep invalid schema values intact for public validation rather than pre-normalizing them.
        param($Value)
        $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $castle.CastlePath 'homepsick.json')
    }
}
AfterAll { $env:HOME = $script:previousHome }

Describe 'Read-only manifest validation and path safety' {
    BeforeEach {
        $env:HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $env:HOME | Out-Null
        $castle = New-HomepsickCastle -CastleName configs
    }

    It 'returns structured errors for <Label>' -ForEach @(
        @{ Label = 'unsupported version'; Manifest = @{ version = 2; roots = @() }; Code = 'UnsupportedVersion' }
        @{ Label = 'noninteger version'; Manifest = @{ version = '1'; roots = @() }; Code = 'UnsupportedVersion' }
        @{ Label = 'missing version'; Manifest = @{ roots = @() }; Code = 'UnsupportedVersion' }
        @{ Label = 'missing roots'; Manifest = @{ version = 1 }; Code = 'InvalidRoots' }
        @{ Label = 'roots object'; Manifest = @{ version = 1; roots = @{} }; Code = 'InvalidRoots' }
        @{ Label = 'root string'; Manifest = @{ version = 1; roots = @('home') }; Code = 'InvalidRoot' }
        @{ Label = 'unknown property'; Manifest = @{ version = 1; roots = @(); typo = 1 }; Code = 'UnknownProperty' }
        @{ Label = 'destinations array'; Manifest = @{ version = 1; roots = @(); destinations = @('home') }; Code = 'InvalidDestinations' }
        @{ Label = 'nonobject destination'; Manifest = @{ version = 1; roots = @(); destinations = @{ editor = 5 } }; Code = 'InvalidDestination' }
        @{ Label = 'nonstring destination path'; Manifest = @{ version = 1; roots = @(); destinations = @{ editor = @{ path = 5 } } }; Code = 'InvalidDestinationPath' }
        @{ Label = 'unknown destination property'; Manifest = @{ version = 1; roots = @(); destinations = @{ editor = @{ path = '~/editor'; typo = 1 } } }; Code = 'UnknownProperty' }
        @{ Label = 'home destination redefinition'; Manifest = @{ version = 1; roots = @(); destinations = @{ home = @{ path = '~/test' } } }; Code = 'InvalidDestination' }
        @{ Label = 'unsafe absolute source'; Manifest = @{ version = 1; roots = @(@{ source = '/home'; target = 'home' }) }; Code = 'InvalidSource' }
        @{ Label = 'source traversal'; Manifest = @{ version = 1; roots = @(@{ source = '../other'; target = 'home' }) }; Code = 'InvalidSource' }
        @{ Label = 'source internal traversal'; Manifest = @{ version = 1; roots = @(@{ source = 'home/../other'; target = 'home' }) }; Code = 'InvalidSource' }
        @{ Label = 'Windows source path'; Manifest = @{ version = 1; roots = @(@{ source = 'C:/home'; target = 'home' }) }; Code = 'InvalidSource' }
        @{ Label = 'source backslash'; Manifest = @{ version = 1; roots = @(@{ source = 'home\other'; target = 'home' }) }; Code = 'InvalidSource' }
        @{ Label = 'reserved Git source'; Manifest = @{ version = 1; roots = @(@{ source = '.git'; target = 'home' }) }; Code = 'InvalidSource' }
        @{ Label = 'reserved device source'; Manifest = @{ version = 1; roots = @(@{ source = 'CON'; target = 'home' }) }; Code = 'InvalidSource' }
        @{ Label = 'unknown target'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'missing' }) }; Code = 'UnknownTarget' }
        @{ Label = 'unknown root property'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; typo = 1 }) }; Code = 'UnknownProperty' }
        @{ Label = 'into traversal'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; into = '../outside' }) }; Code = 'InvalidInto' }
        @{ Label = 'into absolute path'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; into = '/etc' }) }; Code = 'InvalidInto' }
        @{ Label = 'into wildcard'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; into = 'folder*' }) }; Code = 'InvalidInto' }
        @{ Label = 'floating priority'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; priority = 1.5 }) }; Code = 'InvalidPriority' }
        @{ Label = 'string priority'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; priority = '100' }) }; Code = 'InvalidPriority' }
        @{ Label = 'priority overflow'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; priority = 2147483648 }) }; Code = 'InvalidPriority' }
        @{ Label = 'unknown condition'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @{ command = 'pwsh' } }) }; Code = 'UnknownCondition' }
        @{ Label = 'nonobject conditions'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @('linux') }) }; Code = 'InvalidConditions' }
        @{ Label = 'empty condition array'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @{ os = @() } }) }; Code = 'InvalidConditionValue' }
        @{ Label = 'mixed condition array'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @{ os = @('linux', 1) } }) }; Code = 'InvalidConditionValue' }
        @{ Label = 'duplicate condition values'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @{ os = @('linux', 'LINUX') } }) }; Code = 'DuplicateConditionValue' }
        @{ Label = 'unrecognized OS'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @{ os = 'posix' } }) }; Code = 'InvalidConditionValue' }
        @{ Label = 'unrecognized edition'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @{ windowsEdition = 'Professional' } }) }; Code = 'InvalidConditionValue' }
        @{ Label = 'numeric release'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @{ windowsRelease = 11 } }) }; Code = 'InvalidConditionValue' }
        @{ Label = 'incompatible platforms'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @{ distro = 'ubuntu'; windowsRelease = '11' } }) }; Code = 'UnreachableEntry' }
        @{ Label = 'incompatible role and release'; Manifest = @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; when = @{ windowsRole = 'workstation'; windowsRelease = 'server-2022' } }) }; Code = 'UnreachableEntry' }
        @{ Label = 'absolute external destination without declaration'; Manifest = @{ version = 1; roots = @(); destinations = @{ external = @{ path = '/etc/example' } } }; Code = 'OutsideHomeDeclaration' }
        @{ Label = 'outsideHome string'; Manifest = @{ version = 1; roots = @(); destinations = @{ external = @{ path = '/etc/example'; outsideHome = 'true' } } }; Code = 'InvalidOutsideHome' }
        @{ Label = 'destination traversal'; Manifest = @{ version = 1; roots = @(); destinations = @{ external = @{ path = '~/../example' } } }; Code = 'InvalidDestinationPath' }
        @{ Label = 'filesystem root destination'; Manifest = @{ version = 1; roots = @(); destinations = @{ external = @{ path = '/'; outsideHome = $true } } }; Code = 'InvalidDestinationPath' }
        @{ Label = 'environment destination'; Manifest = @{ version = 1; roots = @(); destinations = @{ external = @{ path = '$env:APPDATA/Editor' } } }; Code = 'InvalidDestinationPath' }
    ) {
        Write-ValidationManifest $Manifest
        $result = Test-HomepsickManifest -CastleName configs
        $result.IsValid | Should -BeFalse
        $result.Errors.Code | Should -Contain $Code
        $result.Errors | Where-Object Severity -ne Error | Should -BeNullOrEmpty
    }

    It 'rejects invalid JSON objects and duplicate properties without modifying anything' -ForEach @(
        @{ Json = '{' }
        @{ Json = '[]' }
        @{ Json = '"text"' }
        @{ Json = '{"version":1,"version":2,"roots":[]}' }
        @{ Json = '{"version":1,"roots":[{"source":"home","target":"home","when":{"os":"linux","OS":"windows"}}]}' }
    ) {
        $path = Join-Path $castle.CastlePath 'homepsick.json'
        Set-Content -LiteralPath $path -Value $Json
        $hash = (Get-FileHash -LiteralPath $path).Hash
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'InvalidJson'
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $hash
    }

    # Empty roots cannot prove a file collision, but their conditions can already
    # establish a potential overlap worth surfacing before those files are added.
    It 'reports potentially ambiguous empty overlays with entry identifiers' {
        Write-ValidationManifest @{ version = 1; roots = @(@{ source = 'one'; target = 'home'; when = @{ windowsRelease = '11' } }, @{ source = 'two'; target = 'home'; when = @{ windowsEdition = 'pro' } }) }
        $result = Test-HomepsickManifest -CastleName configs -MachineFacts @{ os = 'linux' }
        $result.IsValid | Should -BeTrue
        $result.Warnings.Code | Should -Contain 'PotentialTie'
        ($result.Warnings | Where-Object Code -eq PotentialTie).Entries | Should -Be @('roots[0]', 'roots[1]')
        $result.Warnings.Code | Should -Contain 'MissingSource'
    }

    It 'accounts for multiple Linux lineages when warning about possible overlap' {
        Write-ValidationManifest @{ version = 1; roots = @(@{ source = 'one'; target = 'home'; when = @{ distroLike = 'rhel' } }, @{ source = 'two'; target = 'home'; when = @{ distroLike = 'fedora' } }) }
        (Test-HomepsickManifest -CastleName configs).Warnings.Code | Should -Contain 'PotentialTie'
    }

    It 'rejects overlapping source directories, including implicit home' {
        New-Item -ItemType Directory -Path (Join-Path $castle.CastleSymRoot 'nested') | Out-Null
        Write-ValidationManifest @{ version = 1; roots = @(@{ source = 'home/nested'; target = 'home' }) }
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'OverlappingSources'
    }

    It 'reports a source declaration that is a file' {
        Set-Content -LiteralPath (Join-Path $castle.CastlePath 'not-a-directory') -Value 'file'
        Write-ValidationManifest @{ version = 1; roots = @(@{ source = 'not-a-directory'; target = 'home' }) }
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'UnsafeSource'
    }

    It 'rejects a symbolic manifest and symbolic source directories' {
        $manifest = Join-Path $castle.CastlePath 'homepsick.json'
        $other = Join-Path $TestDrive 'manifest.json'
        Set-Content -LiteralPath $other -Value '{"version":1,"roots":[]}'
        New-Item -ItemType SymbolicLink -Path $manifest -Target $other | Out-Null
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'InvalidJson'
        Remove-Item -LiteralPath $manifest -Force
        New-Item -ItemType SymbolicLink -Path (Join-Path $castle.CastlePath 'overlay') -Target $castle.CastleSymRoot | Out-Null
        Write-ValidationManifest @{ version = 1; roots = @(@{ source = 'overlay'; target = 'home' }) }
        (Test-HomepsickManifest -CastleName configs).Errors.Code | Should -Contain 'UnsafeSource'
    }

    It 'rejects a selected source link escaping the castle' {
        $outside = Join-Path $TestDrive 'outside-file'
        Set-Content -LiteralPath $outside -Value 'outside'
        New-Item -ItemType SymbolicLink -Path (Join-Path $castle.CastleSymRoot 'example') -Target $outside | Out-Null
        & git -C $castle.CastlePath add home/example
        Write-ValidationManifest @{ version = 1; roots = @() }
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'UnsafeSourceLink'
    }

    It 'allows a tracked symbolic source file resolving safely inside the castle' {
        Set-Content -LiteralPath (Join-Path $castle.CastlePath 'settings') -Value 'internal'
        New-Item -ItemType SymbolicLink -Path (Join-Path $castle.CastleSymRoot 'example') -Target '../settings' | Out-Null
        & git -C $castle.CastlePath add .
        Write-ValidationManifest @{ version = 1; roots = @() }
        (Get-HomepsickLinkPlan -CastleName configs).IsValid | Should -BeTrue
        Enable-HomepsickCastle -CastleName configs -Batch
        Get-Content -LiteralPath (Join-Path $env:HOME 'example') | Should -Be 'internal'
    }

    It 'blocks a symbolic destination parent without modifying its target' {
        Set-Content -LiteralPath (Join-Path $castle.CastleSymRoot 'example') -Value 'settings'
        & git -C $castle.CastlePath add .
        $outside = Join-Path $TestDrive 'redirected'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $env:HOME '.config') -Target $outside | Out-Null
        Write-ValidationManifest @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; into = '.config' }) }
        $plan = Get-HomepsickLinkPlan -CastleName configs
        $plan.Errors.Code | Should -Contain 'UnsafeDestination'
        $plan.Conflicts.ExistingState | Should -Be 'Blocked'
        { Enable-HomepsickCastle -CastleName configs -Force -Batch } | Should -Throw '*Symbolic link*'
        Test-Path -LiteralPath (Join-Path $outside 'example') | Should -BeFalse
    }

    It 'rejects destinations inside castle storage' {
        Set-Content -LiteralPath (Join-Path $castle.CastleSymRoot 'example') -Value 'settings'
        & git -C $castle.CastlePath add .
        Write-ValidationManifest @{ version = 1; roots = @(@{ source = 'home'; target = 'home'; into = '.homesick/repos/victim' }) }
        (Get-HomepsickLinkPlan -CastleName configs).Errors.Code | Should -Contain 'CastleStorageDestination'
    }
}
