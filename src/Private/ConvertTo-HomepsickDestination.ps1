function ConvertTo-HomepsickDestination {
    # Validate every component before lexical normalization. Templates defer parent
    # navigation until expansion, so foreign/inactive variables need not exist here.
    [OutputType([HomepsickDestination])]
    param([object]$Path, [switch]$Literal)

    if ($Path -isnot [string] -or [string]::IsNullOrWhiteSpace($Path)) {
        throw 'Destination must be a nonempty path string.'
    }
    if (-not $Literal -and $Path -match '^(?:%(?<percent>[^%=\x00-\x1f\\/]+)%|\$(?<plain>[A-Za-z_][A-Za-z0-9_]*)|\$\{(?<braced>[A-Za-z_][A-Za-z0-9_]*)\})(?<suffix>(?:[\\/].*)?)$') {
        $variable = $Matches.percent + $Matches.plain + $Matches.braced
        $suffix = $Matches.suffix
        if ($suffix -match '%[^%]+%|\$[A-Za-z_]|\$\{') {
            throw 'Only one leading environment variable is supported.'
        }
        if ($suffix) {
            foreach ($part in ($suffix.Substring(1).Replace('\', '/') -split '/')) {
                if ($part -notin @('.', '..') -and -not (Test-HomepsickRelativePath $part)) {
                    throw 'Destination contains an invalid path component.'
                }
            }
        }
        return [HomepsickDestination]@{ Path = $Path; EnvironmentVariable = $variable; EnvironmentSuffix = $suffix }
    }

    if ($Path -match '^[A-Za-z]:[\\/]') { $Path = $Path.Replace('\', '/') }
    if ($Path -notmatch '^(?<prefix>~/|[A-Za-z]:/|/)(?<relative>.*)$') {
        throw 'Destination requires ~/path, /absolute/path, a drive-absolute Windows subdirectory, or one leading environment variable.'
    }
    $prefix = $Matches.prefix
    $relative = $Matches.relative
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($part in ($relative -split '/')) {
        if ($part -eq '.') { continue }
        if ($part -eq '..') {
            if ($parts.Count -eq 0) { throw 'Destination moves above its home or filesystem anchor.' }
            $parts.RemoveAt($parts.Count - 1)
        }
        elseif (Test-HomepsickRelativePath $part) { $parts.Add($part) }
        else { throw 'Destination contains an invalid path component.' }
    }
    if ($parts.Count -eq 0) { throw 'Destination must identify a subdirectory, not a home or filesystem root.' }
    [HomepsickDestination]@{ Path = $prefix + ($parts -join '/') }
}
