function Enable-HomepsickCastle {
    [CmdletBinding(DefaultParameterSetName="None")]
    param(
        [Parameter(Mandatory=$true, ParameterSetName="Single")]
        [string]$CastleName,
        [Parameter(Mandatory=$true, ParameterSetName="All")]
        [switch]$All,
        [Parameter(Mandatory=$false, ParameterSetName="Single")]
        [Parameter(Mandatory=$false, ParameterSetName="All")]
        [Parameter(Mandatory=$false, ParameterSetName="None")]
        [switch]$Force
    )

    $castles = @()
    if (-not $all)
    {
        $castlePath = [IO.Path]::Combine((Get-HomepsisckPath -Repos), $castleName)
        if (-not (Test-Path $castlePath))
        {
            Throw "Castle $castleName does not exist."
        }
        $castles = @($castlePath)
    }
    else
    {
        $castles = @((Get-ChildItem -Path (Get-HomepsisckPath -Repos) -Directory -Exclude homepsick,homeshick) | Select-Object -ExpandProperty FullName)
    }
    
    $castles | ForEach-Object {
        $castle = $_
        $castleName = [IO.Path]::GetFileName($castle)
        if (-not (Test-Path -PathType Container -Path ([IO.Path]::Combine($castle, 'home'))))
        {
            Throw "Castle $castleName does not have a home directory."
        }
        $CastleSymRoot = [IO.Path]::Combine($castle, 'home')
        $homeRoot = Get-HomePath
        $itemsToLink = Get-ChildItem -Path $CastleSymRoot -Recurse -File -Force

        $itemsToLink | ForEach-Object {
            $item = $_
            $relativePath = $item.FullName.Substring($CastleSymRoot.Length + 1)
            $linkPath = [IO.Path]::Combine($homeRoot, $relativePath)
            $targetPath = $item.FullName.Substring($homeRoot.Length + 1)
            for ($i = 0; $i -lt ($relativePath.Split("\/".ToCharArray())).Count -1; $i++)
            {
                $targetPath = [IO.Path]::Combine('..', $targetPath)
            }
            Write-Host "Linking $linkPath to $targetPath. ($relativePath)"
            if (-not (Test-Path -PathType Leaf -Path $linkPath))
            {
                New-Item -ItemType SymbolicLink -Path $linkPath -Value $targetPath
            }
            else
            {
                if ($Force)
                {
                    Remove-Item -Force $linkPath
                    New-Item -ItemType SymbolicLink -Path $linkPath -Value $targetPath
                }
                else
                {
                    $file = Get-Item -Path $linkPath -Force
                    if ($file.LinkType -ne 'SymbolicLink')
                    {
                        Write-Host "Skipping $linkPath. File already exists."
                    }
                    elseif ($file.Target -eq $targetPath)
                    {
                        Write-Host "Skipping $linkPath. Symbolic link already exists."
                    }
                    elseif ($file.Target -ne $targetPath)
                    {
                        Write-Host "Skipping $linkPath. Symbolic link exists but points to a different target."
                    }
                    else
                    {
                        Write-Host "Skipping $linkPath. File already exists."
                    }
                }
            }
        }
    }
}
