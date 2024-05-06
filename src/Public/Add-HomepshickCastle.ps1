function Add-HomepshickCastle {
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

    $castlePath = [IO.Path]::Combine((Get-HomePath), '.homesick', 'repos', $castleName)
    if (Test-Path $castlePath)
    {
        Throw "Castle $castleName already exists."
    }

    New-Item -ItemType Directory -Path $castlePath
    Set-Location $castlePath
    if (-not $Clone)
    {
        git init
    }
    else
    {
        if (Test-GithubShorthand -stringToTest $GitUrl)
        {
            $GitUrl = "https://github.com/${GitUrl}.git"
        }
        
        # Git Clone
        $gitOut = (git clone $GitUrl . 2>&1)
        
        if ($LASTEXITCODE -ne 0)
        {
            Remove-Item -Recurse -Force $castlePath
            Throw "Failed to clone $GitUrl : $GitOut"
        }

        # Git Submodules Init
        $gitOut = (git submodule update --init 2>&1)
        
        if ($LASTEXITCODE -ne 0)
        {
            Remove-Item -Recurse -Force $castlePath
            Throw "Failed to clone $GitUrl : $GitOut"
        }
    }
}
