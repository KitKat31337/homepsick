function New-HomepsickCastle {
    <#
    .SYNOPSIS
    Initializes an empty castle or clones an existing Git castle.
    .DESCRIPTION
    Initialization creates a Git repository with a home directory. Cloning accepts
    Git URLs, local repositories, or GitHub owner/repo shorthand and initializes
    submodules. The clone directory name is derived from the source repository.
    .PARAMETER CastleName
    Name of the new empty castle. Used only when initializing, without Clone.
    .PARAMETER Clone
    Clones an existing castle instead of initializing an empty one.
    .PARAMETER GitUrl
    Git URL, local repository path, or GitHub owner/repo shorthand. Required with Clone.
    .PARAMETER Link
    Clone only. Links selected content without an initial link prompt.
    Existing destination conflicts still follow the ordinary linking policy.
    .PARAMETER Batch
    Clone only. Suppresses the initial link prompt and skips destination conflicts.
    Combine with Link to link during a noninteractive clone.
    .PARAMETER AllowOutsideHome
    Clone only. Authorizes linking to explicitly declared external destinations.
    .OUTPUTS
    HomepsickCastle. The newly initialized or cloned castle.
    .EXAMPLE
    New-HomepsickCastle -CastleName dotfiles
    Creates an empty Git castle with a home directory ready for file tracking.
    .EXAMPLE
    New-HomepsickCastle -Clone -GitUrl owner/dotfiles -Link -Batch
    Clones a GitHub castle and links selected content while skipping conflicts.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Init', SupportsShouldProcess)]
    [OutputType([HomepsickCastle])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Clone')][switch]$Clone,
        [Parameter(Mandatory, ParameterSetName = 'Clone')][string]$GitUrl,
        [Parameter(Mandatory, ParameterSetName = 'Init')][string]$CastleName,
        [Parameter(ParameterSetName = 'Clone')][switch]$Link,
        [Parameter(ParameterSetName = 'Clone')][switch]$Batch,
        [Parameter(ParameterSetName = 'Clone')][switch]$AllowOutsideHome
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
        $hasContent = if (Test-HomepsickEntry (Join-Path $castle.CastlePath 'homepsick.json')) {
            $plan = Resolve-HomepsickLinkPlan -RepositoryPath $castle.CastlePath
            if (-not $plan.IsValid) { Write-Warning "Cloned castle has an invalid link plan: $((Format-HomepsickDiagnostic $plan.Errors) -join [Environment]::NewLine)" }
            $plan.Winners.Count -gt 0
        } else { Test-Path -LiteralPath $castle.CastleSymRoot -PathType Container }
        if ($Link) { Enable-HomepsickCastle -CastleName $CastleName -Batch:$Batch -AllowOutsideHome:$AllowOutsideHome }
        elseif (-not $Batch -and $hasContent) {
            if ($PSCmdlet.ShouldContinue("Link files from '$CastleName' into the selected destinations?", 'Link cloned castle')) {
                Enable-HomepsickCastle -CastleName $CastleName -AllowOutsideHome:$AllowOutsideHome
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
