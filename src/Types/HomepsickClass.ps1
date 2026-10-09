class HomepsickCastle {
    [string]$CastleName
    [string]$CastlePath
    [string]$CastleSymRoot

    HomepsickCastle() { throw 'A castle name is required.' }

    HomepsickCastle([string]$CastleName) {
        if ([string]::IsNullOrWhiteSpace($CastleName) -or
            $CastleName -in @('.', '..') -or
            $CastleName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
            $CastleName.Contains('/') -or $CastleName.Contains('\')) {
            throw "Invalid castle name: '$CastleName'."
        }
        $this.CastleName = $CastleName
        $this.CastlePath = [IO.Path]::Combine((Get-HomepsickPath -Repos), $CastleName)
        $this.CastleSymRoot = [IO.Path]::Combine($this.CastlePath, 'home')
    }

    [object[]] ItemsToLink() {
        if (-not $this.Exists()) { return @() }
        return @(Get-HomepsickTrackedFile -RepositoryPath $this.CastlePath)
    }

    [string] GitOrigin() {
        if (-not $this.Exists()) { return '' }
        $result = Invoke-HomepsickGit -RepositoryPath $this.CastlePath -Arguments @('config', '--get', 'remote.origin.url') -AllowFailure
        return $result.Output.Trim()
    }

    [bool] Exists() {
        return (Test-Path -LiteralPath $this.CastlePath -PathType Container)
    }

    [void] Update() {
        if (-not $this.Exists()) { throw "Castle '$($this.CastleName)' does not exist." }
        $upstream = Invoke-HomepsickGit -RepositoryPath $this.CastlePath -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}') -AllowFailure
        if ($upstream.ExitCode -ne 0) {
            Write-Verbose "Castle '$($this.CastleName)' has no upstream; skipping pull."
            return
        }
        Invoke-HomepsickGit -RepositoryPath $this.CastlePath -Arguments @('pull') | Out-Null
        Invoke-HomepsickGit -RepositoryPath $this.CastlePath -Arguments @('submodule', 'update', '--init', '--recursive') | Out-Null
    }
}
