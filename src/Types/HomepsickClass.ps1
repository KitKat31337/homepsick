class HomepsickCastle {
    # Default Constructor
    HomepsickCastle () { throw 'HomepsickCastle must be created using the HomepsickCastle([string]$CastleName) constructor.' }

    # Common Constructor
    HomepsickCastle([string]$CastleName) {
        $this.CastleName = $CastleName
        $this.CastlePath = [IO.Path]::Combine((Get-HomepsickPath -Repos), $CastleName)
        $this.CastleSymRoot = [IO.Path]::Combine($this.CastlePath, 'home')
    }

    [string]$CastleName
    [string]$CastlePath
    [string]$CastleSymRoot

    [System.IO.FileInfo[]] ItemsToLink() {
        if ($this.Exists()) { return (Get-ChildItem -Path $this.CastleSymRoot -Recurse -File -Force) }
        else { return $null }
    }
    [string] GitOrigin() {
        if ($this.Exists()) { return (git config --file ([IO.Path]::Combine($this.CastlePath, '.git', 'config')) --get remote.origin.url) }
        else { return $null }
    }

    [bool] Exists() {
        return (Test-Path -Path $this.CastlePath -PathType Container)
    }

    [void] Update() {
        # Git Pull
        Write-Host "Pulling Castle - $($this.CastleName)"
        $gitOut = (git -C $($this.CastlePath) pull 2>&1)
        if ($LASTEXITCODE -ne 0)
        {
            Write-Host "Failed to pull $($this.CastleName) : $GitOut"
        }        
    } 
}