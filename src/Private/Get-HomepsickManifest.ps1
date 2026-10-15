function Get-HomepsickManifest {
    # Validates raw JSON, then returns a normalized HomepsickManifest and diagnostics.
    # Invalid entries never enter the typed root collection. This is read-only;
    # actual tracked-file collisions are resolved by Resolve-HomepsickLinkPlan.
    [CmdletBinding()]
    [OutputType([HomepsickManifest])]
    param([Parameter(Mandatory)][string]$RepositoryPath)

    $issues = [Collections.Generic.List[HomepsickDiagnostic]]::new()
    $roots = [Collections.Generic.List[HomepsickManifestRoot]]::new()
    $destinations = [Collections.Generic.Dictionary[string, HomepsickDestination]]::new([StringComparer]::OrdinalIgnoreCase)
    $manifestPath = Join-Path $RepositoryPath 'homepsick.json'
    $hasManifest = Test-HomepsickEntry $manifestPath
    $addIssue = {
        param($Severity, $Code, $Entries, $Message)
        $issues.Add([HomepsickDiagnostic]@{ Severity = $Severity; Code = $Code; Entries = @($Entries); Message = $Message })
    }
    # Validate JSON shape and duplicate keys before normalizing case-insensitive data.
    $data = $null
    if ($hasManifest) {
        try {
            $item = Get-Item -LiteralPath $manifestPath -Force
            if ($item.PSIsContainer -or $item.LinkType) { throw 'homepsick.json must be a regular file, not a symbolic link or directory.' }
            $json = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
            $document = [System.Text.Json.JsonDocument]::Parse($json)
            try { Assert-HomepsickJsonProperty $document.RootElement }
            finally { $document.Dispose() }
            $data = ConvertFrom-Json -InputObject $json -AsHashtable -ErrorAction Stop
            if ($data -isnot [System.Collections.IDictionary]) { throw 'The manifest must be a JSON object.' }
        }
        catch {
            & $addIssue Error InvalidJson @() $_.Exception.Message
            $data = $null
        }
    }
    if ($null -ne $data) {
        foreach ($key in $data.Keys) {
            if ($key -cnotin @('version', 'destinations', 'roots')) { & $addIssue Error UnknownProperty @() "Unknown manifest property '$key'." }
        }
        if ($data.version -isnot [long] -and $data.version -isnot [int] -or $data.version -ne 1) {
            & $addIssue Error UnsupportedVersion @() 'Manifest version must be the integer 1.'
        }
        if ($data.roots -isnot [array]) { & $addIssue Error InvalidRoots @() 'roots must be an array.' }
        # Destination declarations stay literal; external writes need a separate opt-in.
        if ($data.Contains('destinations') -and $data.destinations -isnot [System.Collections.IDictionary]) {
            & $addIssue Error InvalidDestinations @() 'destinations must be an object.'
        }
        elseif ($data.destinations) {
            foreach ($name in $data.destinations.Keys) {
                $startErrors = @($issues | Where-Object Severity -eq Error).Count
                $destination = $data.destinations[$name]
                if ($name -eq 'home' -or $name -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
                    & $addIssue Error InvalidDestination @() "Destination name '$name' is invalid or reserved."
                    continue
                }
                if ($destination -isnot [System.Collections.IDictionary]) {
                    & $addIssue Error InvalidDestination @() "Destination '$name' must be an object."
                    continue
                }
                foreach ($key in $destination.Keys) {
                    if ($key -cnotin @('path', 'outsideHome')) { & $addIssue Error UnknownProperty @() "Unknown property '$key' in destination '$name'." }
                }
                $path = $destination.path
                # Only drive-absolute Windows destinations accept backslashes.
                # Normalize their separators before portable validation; UNC/device
                # prefixes and backslashes in source/into/home-relative paths stay invalid.
                $portablePath = if ($path -is [string] -and $path -match '^[A-Za-z]:[\\/]') {
                    $path.Replace('\', '/')
                } else { $path }
                $relative = if ($portablePath -is [string]) { $portablePath -replace '^(~/|/|[A-Za-z]:/)', '' } else { $null }
                if ($portablePath -isnot [string] -or $portablePath -notmatch '^(~/|/|[A-Za-z]:/)' -or -not (Test-HomepsickRelativePath $relative)) {
                    & $addIssue Error InvalidDestinationPath @() "Destination '$name' requires a literal ~/path, /absolute/path, or drive-absolute Windows subdirectory without traversal."
                    continue
                }
                if ($destination.Contains('outsideHome') -and $destination.outsideHome -isnot [bool]) {
                    & $addIssue Error InvalidOutsideHome @() "outsideHome on '$name' must be a boolean."
                }
                if (-not $portablePath.StartsWith('~/') -and $destination.outsideHome -ne $true) {
                    $insideHome = $false
                    try {
                        $resolved = Resolve-HomepsickDestination -Path $portablePath -HomePath (Get-HomePath)
                        $insideHome = Test-HomepsickContainedPath -Parent ([IO.Path]::GetFullPath((Get-HomePath))) -Path $resolved -AllowEqual
                    }
                    catch { $insideHome = $false }
                    if (-not $insideHome) {
                        & $addIssue Error OutsideHomeDeclaration @() "Destination '$name' requires outsideHome: true. Use ~/ for portable home-relative destinations."
                    }
                }
                if (@($issues | Where-Object Severity -eq Error).Count -ne $startErrors) { continue }
                $destinations[$name] = [HomepsickDestination]@{ Path = $portablePath; OutsideHome = ($destination.outsideHome -eq $true) }
            }
        }
        # Validate each raw root before converting it into the shared root contract.
        $index = 0
        foreach ($entry in @($data.roots)) {
            $id = "roots[$index]"
            $index++
            $startErrors = @($issues | Where-Object Severity -eq Error).Count
            if ($entry -isnot [System.Collections.IDictionary]) {
                & $addIssue Error InvalidRoot $id 'Each root must be an object.'
                continue
            }
            foreach ($key in $entry.Keys) {
                if ($key -cnotin @('source', 'target', 'into', 'when', 'priority')) { & $addIssue Error UnknownProperty $id "Unknown root property '$key'." }
            }
            if (-not (Test-HomepsickRelativePath $entry.source)) { & $addIssue Error InvalidSource $id 'source must be a relative directory path using forward slashes, without traversal.' }
            if ($entry.target -isnot [string] -or ($entry.target -cne 'home' -and -not $destinations.ContainsKey($entry.target))) {
                & $addIssue Error UnknownTarget $id "Unknown target '$($entry.target)'."
            }
            if ($entry.Contains('into') -and -not (Test-HomepsickRelativePath $entry.into)) { & $addIssue Error InvalidInto $id 'into must be a relative directory path without traversal.' }
            if ($entry.Contains('priority') -and (($entry.priority -isnot [int] -and $entry.priority -isnot [long]) -or
                $entry.priority -lt [int]::MinValue -or $entry.priority -gt [int]::MaxValue)) {
                & $addIssue Error InvalidPriority $id 'priority must be a signed 32-bit integer.'
            }
            $when = @{}
            if ($entry.Contains('when') -and $entry.when -isnot [System.Collections.IDictionary]) {
                & $addIssue Error InvalidConditions $id 'when must be an object.'
            }
            elseif ($entry.when) {
                foreach ($key in $entry.when.Keys) {
                    if ($key -cnotin @('os', 'distroLike', 'distro', 'distroVersion', 'windowsRole', 'windowsRelease', 'windowsEdition', 'host')) {
                        & $addIssue Error UnknownCondition $id "Unknown condition '$key'."
                        continue
                    }
                    $values = @($entry.when[$key])
                    if (-not $values.Count -or @($values | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count) {
                        & $addIssue Error InvalidConditionValue $id "'$key' requires a nonempty string or nonempty array of strings."
                        continue
                    }
                    $values = @($values | ForEach-Object { $_.Trim().ToLowerInvariant() })
                    if (@($values | Select-Object -Unique).Count -ne $values.Count) { & $addIssue Error DuplicateConditionValue $id "'$key' contains duplicate values." }
                    foreach ($value in $values) {
                        $valid = switch ($key) {
                            os { $value -in @('windows', 'linux', 'macos', 'freebsd') }
                            windowsRole { $value -in @('workstation', 'server') }
                            windowsRelease { $value -match '^(\d+(\.\d+)?|server-\d{4}(-r2)?)$' }
                            windowsEdition { $value -in @('home', 'pro', 'enterprise', 'education', 'standard', 'datacenter') }
                            default { $value -match '^[a-z0-9][a-z0-9._-]*$' }
                        }
                        if (-not $valid) { & $addIssue Error InvalidConditionValue $id "Invalid canonical $key value '$value'." }
                    }
                    $when[$key] = $values
                }
            }
            $destinationOS = @()
            if ($entry.target -is [string] -and $destinations.ContainsKey($entry.target)) {
                $destinationPath = $destinations[$entry.target].Path
                if ($destinationPath -match '^[A-Za-z]:/') { $destinationOS = @('windows') }
            }
            if (-not @(Get-HomepsickConditionOS -When $when -DestinationOS $destinationOS).Count) {
                & $addIssue Error UnreachableEntry $id 'Conditions and destination require incompatible operating systems.'
            }
            if ($when.Contains('windowsRole') -and $when.Contains('windowsRelease')) {
                $releaseRoles = @($when.windowsRelease | ForEach-Object { if ($_ -like 'server-*') { 'server' } else { 'workstation' } })
                if (-not @($releaseRoles | Where-Object { $_ -in $when.windowsRole }).Count) {
                    & $addIssue Error UnreachableEntry $id 'Windows role and release conditions are incompatible.'
                }
            }
            if (@($issues | Where-Object Severity -eq Error).Count -ne $startErrors) { continue }
            $calculated = Get-HomepsickRootPriority $when
            $roots.Add([HomepsickManifestRoot]@{
                Entry = $id; Source = $entry.source; Target = $entry.target; Into = [string]$entry.into; When = $when
                DestinationOS = $destinationOS
                CalculatedPriority = $calculated; PriorityOverridden = $entry.Contains('priority')
                Priority = if ($entry.Contains('priority')) { [int]$entry.priority } else { $calculated }; Implicit = $false
            })
        }
    }
    # An explicit home declaration replaces the implicit legacy root, never duplicates it.
    if (-not @($roots | Where-Object Source -eq 'home').Count -and (Test-Path -LiteralPath (Join-Path $RepositoryPath 'home') -PathType Container)) {
        $roots.Insert(0, [HomepsickManifestRoot]@{
            Entry = 'implicit home'; Source = 'home'; Target = 'home'; Into = ''; When = @{}
            Priority = 0; CalculatedPriority = 0; PriorityOverridden = $false; Implicit = $true
        })
    }
    # Check source safety and cross-root relationships independently of this machine.
    # Potential overlaps warn here; concrete highest-priority file ties fail in the plan.
    if ($hasManifest) {
        foreach ($root in $roots) {
            $sourcePath = [IO.Path]::Combine($RepositoryPath, $root.Source)
            $obstacle = Get-HomepsickPathObstacle -Path $sourcePath -StopAt $RepositoryPath -IncludeLeaf
            if ($obstacle) { & $addIssue Error UnsafeSource $root.Entry $obstacle }
            elseif (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) { & $addIssue Warning MissingSource $root.Entry "Source directory '$($root.Source)' is absent." }
        }
        for ($i = 0; $i -lt $roots.Count; $i++) {
            for ($j = $i + 1; $j -lt $roots.Count; $j++) {
                $left = $roots[$i]
                $right = $roots[$j]
                $ids = @($left.Entry, $right.Entry)
                $sameConditions = $left.When.Count -eq $right.When.Count
                foreach ($key in $left.When.Keys) {
                    if (-not $right.When.Contains($key) -or
                        @($left.When[$key]).Count -ne @($right.When[$key]).Count -or
                        @($left.When[$key] | Where-Object { $_ -notin @($right.When[$key]) }).Count) {
                        $sameConditions = $false
                        break
                    }
                }
                if ($left.Source -ceq $right.Source -and $left.Target -ceq $right.Target -and
                    $left.Into -ceq $right.Into -and $left.Priority -eq $right.Priority -and $sameConditions) {
                    & $addIssue Error DuplicateRoot $ids 'Identical root declarations must not be processed twice.'
                }
                if ($left.Source.StartsWith($right.Source + '/', [StringComparison]::OrdinalIgnoreCase) -or
                    $right.Source.StartsWith($left.Source + '/', [StringComparison]::OrdinalIgnoreCase)) {
                    & $addIssue Error OverlappingSources $ids 'Source roots must not contain one another.'
                }
                if (-not (Test-HomepsickConditionsOverlap -Left $left -Right $right)) { continue }
                try {
                    $bases = foreach ($root in @($left, $right)) {
                        $base = if ($root.Target -eq 'home') { [IO.Path]::GetFullPath((Get-HomePath)) }
                            else { Resolve-HomepsickDestination -Path $destinations[$root.Target].Path -HomePath (Get-HomePath) }
                        if ($root.Into) { $base = [IO.Path]::GetFullPath([IO.Path]::Combine($base, $root.Into)) }
                        $base
                    }
                    if (-not (Test-HomepsickContainedPath -Parent $bases[0] -Path $bases[1] -AllowEqual) -and
                        -not (Test-HomepsickContainedPath -Parent $bases[1] -Path $bases[0] -AllowEqual)) { continue }
                }
                catch {
                    # A foreign-platform absolute destination cannot be resolved here;
                    # retain a conservative warning rather than rejecting that manifest.
                    $bases = $null
                }
                if ($left.Priority -eq $right.Priority) {
                    # Named destinations can alias one another; actual files are resolved by
                    # the plan. Static checking warns even if the directories are empty today.
                    & $addIssue Warning PotentialTie $ids 'These entries can match together at equal priority. If their destination files overlap, linking fails; set priorities or mutually exclusive conditions.'
                }
                if ($left.Source -eq $right.Source -and $left.Target -eq $right.Target -and $left.Into -eq $right.Into -and
                    ($left.When.Count -eq 0 -or $right.When.Count -eq 0)) {
                    if ($left.When.Count -eq 0 -and $left.Priority -gt $right.Priority) {
                        & $addIssue Warning ShadowedEntry $right.Entry "Entry is always shadowed by '$($left.Entry)'."
                    }
                    elseif ($right.When.Count -eq 0 -and $right.Priority -gt $left.Priority) {
                        & $addIssue Warning ShadowedEntry $left.Entry "Entry is always shadowed by '$($right.Entry)'."
                    }
                }
            }
        }
    }
    [HomepsickManifest]@{
        HasManifest = [bool]$hasManifest; Roots = @($roots); Destinations = $destinations
        Errors = @($issues | Where-Object Severity -eq Error); Warnings = @($issues | Where-Object Severity -eq Warning)
    }
}
