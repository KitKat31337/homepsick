function New-HomepsickCastle {
    [CmdletBinding(DefaultParameterSetName = 'Init', SupportsShouldProcess)]
    [OutputType([HomepsickCastle])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Clone')][switch]$Clone,
        [Parameter(Mandatory, ParameterSetName = 'Clone')][string]$GitUrl,
        [Parameter(Mandatory, ParameterSetName = 'Init')][string]$CastleName,
        [Parameter(ParameterSetName = 'Clone')][switch]$Link,
        [Parameter(ParameterSetName = 'Clone')][switch]$Batch
    )

    if (-not (Test-PathCommand -command 'git')) { throw 'git is not installed.' }
    if ($Clone) {
        # Work with HTTPS, local paths, and scp-style SSH URLs.
        $source = $GitUrl.TrimEnd('/', '\') -replace '\.git$', ''
        $CastleName = ($source -split '[:/\\]')[-1]
        if (Test-GithubShorthand -stringToTest $GitUrl) {
            $GitUrl = "https://github.com/$GitUrl.git"
        }
    }
    $castle = [HomepsickCastle]::new($CastleName)
    if (Test-HomepsickEntry -LiteralPath $castle.CastlePath) { throw "Castle '$CastleName' already exists." }
    if (-not $PSCmdlet.ShouldProcess($castle.CastlePath, $(if ($Clone) { 'Clone castle' } else { 'Generate castle' }))) { return }

    $repos = Get-HomepsickPath -Repos
    New-Item -ItemType Directory -Path $repos -Force | Out-Null
    if ($Clone) {
        try {
            Invoke-HomepsickGit -RepositoryPath $repos -Arguments @('clone', '--recursive', $GitUrl, $CastleName) | Out-Null
        }
        catch {
            # Only remove a directory created by this failed clone.
            if (Test-Path -LiteralPath $castle.CastlePath -PathType Container) {
                Remove-Item -LiteralPath $castle.CastlePath -Recurse -Force
            }
            throw
        }
        if ($Link) { Enable-HomepsickCastle -CastleName $CastleName -Batch:$Batch }
        elseif (-not $Batch -and (Test-Path -LiteralPath $castle.CastleSymRoot -PathType Container)) {
            if ($PSCmdlet.ShouldContinue("Link files from '$CastleName' into your home directory?", 'Link cloned castle')) {
                Enable-HomepsickCastle -CastleName $CastleName
            }
        }
    }
    else {
        New-Item -ItemType Directory -Path $castle.CastlePath | Out-Null
        Invoke-HomepsickGit -RepositoryPath $castle.CastlePath -Arguments @('init') | Out-Null
        New-Item -ItemType Directory -Path $castle.CastleSymRoot | Out-Null
    }
    return $castle
}
