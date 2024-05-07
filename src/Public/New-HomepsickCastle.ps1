function New-HomepsickCastle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName="Clone")]
        [switch]$Clone,
        [Parameter(Mandatory=$true, ParameterSetName="Clone")]
        [string]$GitUrl,
        [Parameter(Mandatory=$true, ParameterSetName="Init")]
        [string]$CastleName
    )

    if (-not (Test-PathCommand -command "git"))
    {
        Throw "git is not installed."
    }

    if($Clone)
    {
        $CastleName = (Split-Path -LeafBase $GitUrl)
    }

    $castle = [HomepsickCastle]::new($CastleName)
    if (Test-Path $castle.CastlePath)
    {
        Throw "Castle $CastleName already exists."
    }

    New-Item -ItemType Directory -Path $castle.CastlePath
    if (-not $Clone)
    {
        git -C "$($castle.CastlePath)" init
    }
    else
    {
        if (Test-GithubShorthand -stringToTest $GitUrl)
        {
            $GitUrl = "https://github.com/${GitUrl}.git"
        }
        
        # Git Clone
        $gitOut = (git -C "$($castle.CastlePath)" clone $GitUrl . 2>&1)
        
        if ($LASTEXITCODE -ne 0)
        {
            Remove-Item -Recurse -Force $castlePath
            Throw "Failed to clone $GitUrl : $GitOut"
        }

        # Git Submodules Init
        $gitOut = (git -C "$($castle.CastlePath)" submodule update --init 2>&1)
        
        if ($LASTEXITCODE -ne 0)
        {
            Remove-Item -Recurse -Force $castlePath
            Throw "Failed to clone $GitUrl : $GitOut"
        }
    }
}
