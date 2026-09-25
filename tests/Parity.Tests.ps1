BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/Homepsick.psm1') -Force
    $script:previousHome = $env:HOME

    function New-TestSource {
        param([string]$Path)
        & git init --initial-branch=main $Path | Out-Null
        & git -C $Path config user.email 'tests@example.invalid'
        & git -C $Path config user.name 'Homepsick Tests'
        New-Item -ItemType Directory -Path (Join-Path $Path 'home') | Out-Null
        Set-Content -LiteralPath (Join-Path $Path 'home/.example') -Value 'original'
        & git -C $Path add .
        & git -C $Path commit -m 'Initial castle' | Out-Null
    }
}

AfterAll { $env:HOME = $script:previousHome }

Describe 'Castle lifecycle' {
BeforeEach {
    $env:HOME = Join-Path $TestDrive 'user'
    if (Test-Path -LiteralPath $env:HOME) { Remove-Item -LiteralPath $env:HOME -Recurse -Force }
    $sourcePath = Join-Path $TestDrive 'source'
    if (Test-Path -LiteralPath $sourcePath) { Remove-Item -LiteralPath $sourcePath -Recurse -Force }
    New-Item -ItemType Directory -Path $env:HOME | Out-Null
}

    It 'generates a Git castle with a home directory and lists only castles' {
        $castle = New-HomepsickCastle -CastleName dotfiles
        (Test-Path -LiteralPath $castle.CastleSymRoot -PathType Container) | Should -BeTrue
        New-Item -ItemType Directory -Path (Join-Path $env:HOME '.homesick/repos/not-a-castle') | Out-Null
        @(Get-HomepsickCastle).CastleName | Should -Be @('dotfiles')
    }

    It 'tracks a home file and stages it in Git' {
        $castle = New-HomepsickCastle -CastleName dotfiles
        $source = Join-Path $env:HOME '.example'
        Set-Content -LiteralPath $source -Value 'my settings'
        Add-HomepsickFile -CastleName dotfiles -Path $source
        (Get-Item -LiteralPath $source -Force).LinkType | Should -Be 'SymbolicLink'
        (Get-Content -LiteralPath (Join-Path $castle.CastleSymRoot '.example')) | Should -Be 'my settings'
        (& git -C $castle.CastlePath diff --cached --name-only).Trim() | Should -Be 'home/.example'
    }

    It 'links tracked files, skips conflicts, and supports WhatIf' {
        $castle = New-HomepsickCastle -CastleName dotfiles
        Set-Content -LiteralPath (Join-Path $castle.CastleSymRoot '.tracked') -Value 'tracked'
        Set-Content -LiteralPath (Join-Path $castle.CastleSymRoot '.ignored') -Value 'untracked'
        & git -C $castle.CastlePath add home/.tracked
        $link = Join-Path $env:HOME '.tracked'
        Enable-HomepsickCastle -CastleName dotfiles -WhatIf
        (Test-Path -LiteralPath $link) | Should -BeFalse
        Set-Content -LiteralPath $link -Value 'existing'
        Enable-HomepsickCastle -CastleName dotfiles -Batch
        (Get-Content -LiteralPath $link) | Should -Be 'existing'
        Enable-HomepsickCastle -CastleName dotfiles -Force -Batch
        (Get-Item -LiteralPath $link -Force).LinkType | Should -Be 'SymbolicLink'
        (Test-Path -LiteralPath (Join-Path $env:HOME '.ignored')) | Should -BeFalse
    }

    It 'links nested tracked names with spaces and replaces a broken link' {
        $castle = New-HomepsickCastle -CastleName dotfiles
        $directory = Join-Path $castle.CastleSymRoot '.config/folder with spaces'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $directory 'my file.txt') -Value 'working'
        & git -C $castle.CastlePath add .
        $link = Join-Path $env:HOME '.config/folder with spaces/my file.txt'
        New-Item -ItemType Directory -Path (Split-Path -Parent $link) -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path $link -Target 'missing-file' | Out-Null
        Enable-HomepsickCastle -CastleName dotfiles -Force -Batch
        (Get-Content -LiteralPath $link) | Should -Be 'working'
    }

    It 'rejects tracking files outside the home directory' {
        New-HomepsickCastle -CastleName dotfiles | Out-Null
        $outside = Join-Path $TestDrive 'outside'
        Set-Content -LiteralPath $outside -Value 'do not move'
        { Add-HomepsickFile -CastleName dotfiles -Path $outside } | Should -Throw '*must be inside the home directory*'
        (Get-Content -LiteralPath $outside) | Should -Be 'do not move'
    }

    It 'clones, checks, pulls, links new files, and enters a castle' {
        $source = Join-Path $TestDrive 'source'
        New-TestSource $source
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Batch
        $castle.CastleName | Should -Be 'source'
        (Get-HomepsickCastleStatus -CastleName source).Status | Should -Be 'Current'
        Set-Content -LiteralPath (Join-Path $source 'home/.second') -Value 'second'
        & git -C $source add .
        & git -C $source commit -m 'Add another file' | Out-Null
        (Get-HomepsickCastleStatus -CastleName source).Status | Should -Be 'Behind'
        Update-HomepsickCastle -CastleName source -Link -Batch
        (Get-Item -LiteralPath (Join-Path $env:HOME '.second') -Force).LinkType | Should -Be 'SymbolicLink'
        (Get-HomepsickCastleStatus -CastleName source).Status | Should -Be 'Current'
        Push-Location
        try {
            Enter-HomepsickCastle -CastleName source
            (Get-Location).Path | Should -Be $castle.CastlePath
        }
        finally { Pop-Location }
    }

    It 'refreshes only stale castles when explicitly told to pull' {
        $source = Join-Path $TestDrive 'source'
        New-TestSource $source
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Batch
        Set-Content -LiteralPath (Join-Path $source 'home/.second') -Value 'second'
        & git -C $source add .
        & git -C $source commit -m 'Update' | Out-Null
        Invoke-HomepsickCastleRefresh -CastleName source -Days 0 -Pull -Batch
        (Test-Path -LiteralPath (Join-Path $castle.CastleSymRoot '.second')) | Should -BeTrue
    }

    It 'links files tracked inside a submodule under home' {
        $subSource = Join-Path $TestDrive 'subsource'
        & git init --initial-branch=main $subSource | Out-Null
        & git -C $subSource config user.email 'tests@example.invalid'
        & git -C $subSource config user.name 'Homepsick Tests'
        Set-Content -LiteralPath (Join-Path $subSource 'nested.txt') -Value 'from submodule'
        & git -C $subSource add .
        & git -C $subSource commit -m 'Submodule file' | Out-Null
        $source = Join-Path $TestDrive 'source'
        New-TestSource $source
        $previousProtocols = $env:GIT_ALLOW_PROTOCOL
        $env:GIT_ALLOW_PROTOCOL = 'file'
        try {
            & git -C $source submodule add $subSource home/sub | Out-Null
            & git -C $source commit -am 'Add submodule' | Out-Null
            New-HomepsickCastle -Clone -GitUrl $source -Batch | Out-Null
            Enable-HomepsickCastle -CastleName source -Batch
            (Get-Content -LiteralPath (Join-Path $env:HOME 'sub/nested.txt')) | Should -Be 'from submodule'
        }
        finally { $env:GIT_ALLOW_PROTOCOL = $previousProtocols }
    }

    It 'reports local changes, local commits, and castles without upstreams' {
        $source = Join-Path $TestDrive 'source'
        New-TestSource $source
        $castle = New-HomepsickCastle -Clone -GitUrl $source -Batch
        Set-Content -LiteralPath (Join-Path $castle.CastleSymRoot '.example') -Value 'modified'
        (Get-HomepsickCastleStatus -CastleName source).Status | Should -Be 'Modified'
        & git -C $castle.CastlePath config user.email 'tests@example.invalid'
        & git -C $castle.CastlePath config user.name 'Homepsick Tests'
        & git -C $castle.CastlePath add .
        & git -C $castle.CastlePath commit -m 'Local change' | Out-Null
        (Get-HomepsickCastleStatus -CastleName source).Status | Should -Be 'Ahead'
        New-HomepsickCastle -CastleName local | Out-Null
        (Get-HomepsickCastleStatus -CastleName local).Status | Should -Be 'Uncheckable'
    }
}
