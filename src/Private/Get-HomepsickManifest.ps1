function Assert-HomepsickJsonProperty {
    param([System.Text.Json.JsonElement]$Element)
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw "Duplicate JSON property '$($property.Name)'." }
            Assert-HomepsickJsonProperty $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-HomepsickJsonProperty $item }
    }
}

function Get-HomepsickManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryPath)

    $issues = [Collections.Generic.List[object]]::new()
    $roots = [Collections.Generic.List[object]]::new()
    $destinations = @{}
    $manifestPath = Join-Path $RepositoryPath 'homepsick.json'
    $hasManifest = Test-HomepsickEntry $manifestPath
    $addIssue = {
        param($Severity, $Code, $Entries, $Message)
        $issues.Add([pscustomobject]@{ Severity = $Severity; Code = $Code; Entries = @($Entries); Message = $Message })
    }
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
        if ($data.Contains('destinations') -and $data.destinations -isnot [System.Collections.IDictionary]) {
            & $addIssue Error InvalidDestinations @() 'destinations must be an object.'
        }
        elseif ($data.destinations) {
            foreach ($name in $data.destinations.Keys) {
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
                $relative = if ($path -is [string]) { $path -replace '^(~/|/|[A-Za-z]:/)', '' } else { $null }
                if ($path -isnot [string] -or $path -notmatch '^(~/|/|[A-Za-z]:/)' -or -not (Test-HomepsickRelativePath $relative)) {
                    & $addIssue Error InvalidDestinationPath @() "Destination '$name' requires a literal ~/path, /absolute/path, or C:/absolute/path without traversal."
                    continue
                }
                if ($destination.Contains('outsideHome') -and $destination.outsideHome -isnot [bool]) {
                    & $addIssue Error InvalidOutsideHome @() "outsideHome on '$name' must be a boolean."
                }
                if (-not $path.StartsWith('~/') -and $destination.outsideHome -ne $true) {
                    $insideHome = $false
                    try {
                        $resolved = Resolve-HomepsickDestination -Path $path -HomePath (Get-HomePath)
                        $insideHome = Test-HomepsickContainedPath -Parent ([IO.Path]::GetFullPath((Get-HomePath))) -Path $resolved -AllowEqual
                    }
                    catch { $insideHome = $false }
                    if (-not $insideHome) {
                        & $addIssue Error OutsideHomeDeclaration @() "Destination '$name' requires outsideHome: true. Use ~/ for portable home-relative destinations."
                    }
                }
                $destinations[$name] = [pscustomobject]@{ Path = $path; OutsideHome = ($destination.outsideHome -eq $true) }
            }
        }
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
            if (-not @(Get-HomepsickConditionOS $when).Count) { & $addIssue Error UnreachableEntry $id 'Conditions require incompatible operating systems.' }
            if ($when.Contains('windowsRole') -and $when.Contains('windowsRelease')) {
                $releaseRoles = @($when.windowsRelease | ForEach-Object { if ($_ -like 'server-*') { 'server' } else { 'workstation' } })
                if (-not @($releaseRoles | Where-Object { $_ -in $when.windowsRole }).Count) {
                    & $addIssue Error UnreachableEntry $id 'Windows role and release conditions are incompatible.'
                }
            }
            if (@($issues | Where-Object Severity -eq Error).Count -ne $startErrors) { continue }
            $calculated = Get-HomepsickRootPriority $when
            $roots.Add([pscustomobject]@{
                Entry = $id; Source = $entry.source; Target = $entry.target; Into = [string]$entry.into; When = $when
                CalculatedPriority = $calculated; PriorityOverridden = $entry.Contains('priority')
                Priority = if ($entry.Contains('priority')) { [int]$entry.priority } else { $calculated }; Implicit = $false
            })
        }
    }
    if (-not @($roots | Where-Object Source -eq 'home').Count -and (Test-Path -LiteralPath (Join-Path $RepositoryPath 'home') -PathType Container)) {
        $roots.Insert(0, [pscustomobject]@{
            Entry = 'implicit home'; Source = 'home'; Target = 'home'; Into = ''; When = @{}
            Priority = 0; CalculatedPriority = 0; PriorityOverridden = $false; Implicit = $true
        })
    }
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
                if ($left.Source.StartsWith($right.Source + '/', [StringComparison]::OrdinalIgnoreCase) -or
                    $right.Source.StartsWith($left.Source + '/', [StringComparison]::OrdinalIgnoreCase)) {
                    & $addIssue Error OverlappingSources $ids 'Source roots must not contain one another.'
                }
                if (-not (Test-HomepsickConditionsOverlap $left.When $right.When)) { continue }
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
    [pscustomobject]@{
        HasManifest = [bool]$hasManifest; Roots = @($roots); Destinations = $destinations
        Errors = @($issues | Where-Object Severity -eq Error); Warnings = @($issues | Where-Object Severity -eq Warning)
    }
}
