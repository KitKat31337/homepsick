function Resolve-HomepsickTrackingPath {
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][string]$Path,
        [string]$Root,
        [switch]$AllowOutsideHome
    )

    $choices = @($Plan.Entries | Where-Object {
        $_.Selected -and $_.DestinationPath -and
        (Test-HomepsickContainedPath -Parent $_.DestinationPath -Path $Path)
    })
    if ($Root) {
        $choices = @($choices | Where-Object { $_.Entry -ceq $Root -or $_.Source -ceq $Root })
    }
    if (-not $choices.Count) {
        throw "[NoTrackingRoot] No applicable root$(if ($Root) { " '$Root'" }) maps '$Path'. Inspect Get-HomepsickLinkPlan for selected roots and destinations."
    }
    if ($choices.Count -gt 1) {
        throw "[AmbiguousTrackingRoot] $($choices.Entry -join ', '): Multiple roots map '$Path'. Choose one with -Root using its source directory or roots[n] identifier."
    }
    $choice = $choices[0]
    if ($choice.OutsideHome -and -not $AllowOutsideHome) {
        throw "[OutsideHomeOptIn] $($choice.Entry): Tracking '$Path' requires -AllowOutsideHome."
    }
    $relative = [IO.Path]::GetRelativePath($choice.DestinationPath, $Path).Replace('\', '/')
    if (-not (Test-HomepsickRelativePath $relative)) {
        throw "[UnsafeTrackingPath] $($choice.Entry): '$relative' is not a safe portable relative path."
    }
    if (Test-HomepsickContainedPath -Parent (Get-HomepsickPath -Root) -Path $Path -AllowEqual) {
        throw "[CastleStorageDestination] $($choice.Entry): Files inside castle storage cannot be tracked as destination files."
    }
    $source = [IO.Path]::GetFullPath([IO.Path]::Combine($Plan.RepositoryPath, $choice.Source, $relative))
    foreach ($obstacle in @(
        (Get-HomepsickPathObstacle -Path $Path),
        (Get-HomepsickPathObstacle -Path $source -StopAt $Plan.RepositoryPath)
    )) {
        if ($obstacle) { throw "[UnsafeTrackingPath] $($choice.Entry): $obstacle" }
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer) { throw "[UnsafeTrackingPath] $($choice.Entry): Directory symbolic links cannot be tracked in manifest castles." }
    [pscustomobject]@{
        Entry = $choice.Entry; SourcePath = $source; RelativePath = $relative
        RepositoryRelativePath = "$($choice.Source)/$relative"
    }
}
