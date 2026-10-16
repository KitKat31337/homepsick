function Test-HomepsickRelativePath {
    # Returns whether raw data is a portable relative path with no traversal.
    # Apply Windows filename restrictions on every host so a manifest travels safely.
    param([object]$Path)
    if ($Path -isnot [string] -or [string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '[\\:\x00-\x1f*?\[\]<>"|]' -or $Path.StartsWith('/')) { return $false }
    foreach ($part in ($Path -split '/')) {
        if ($part -in @('', '.', '..', '.git') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            $part -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)') { return $false }
    }
    return $true
}
