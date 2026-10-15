function Resolve-HomepsickDestination {
    # Expand a selected destination as data, then normalize before authorization.
    # Environment values are never evaluated or recursively expanded. Foreign
    # absolute paths must not become relative paths on the executing filesystem.
    param([string]$Path, [string]$HomePath)
    $declaredPath = $Path
    $destination = ConvertTo-HomepsickDestination -Path $Path
    if ($destination.EnvironmentVariable) {
        $value = [Environment]::GetEnvironmentVariable($destination.EnvironmentVariable, [EnvironmentVariableTarget]::Process)
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Destination environment variable '$($destination.EnvironmentVariable)' is missing or empty."
        }
        if ($value -notmatch '^(?:[A-Za-z]:[\\/]|/)') {
            throw "Destination environment variable '$($destination.EnvironmentVariable)' must contain an absolute path."
        }
        # Accept one trailing directory separator without hiding repeated/UNC
        # separators from component validation when joining the suffix.
        if ($value.EndsWith('/') -or $value.EndsWith('\')) { $value = $value.Substring(0, $value.Length - 1) }
        $expanded = $value + $destination.EnvironmentSuffix
        $destination = ConvertTo-HomepsickDestination -Path $expanded -Literal
    }
    $Path = $destination.Path
    if ($Path.StartsWith('~/')) { return [IO.Path]::GetFullPath([IO.Path]::Combine($HomePath, $Path.Substring(2))) }
    if (($Path -match '^[A-Za-z]:/' -and -not $IsWindows) -or ($Path.StartsWith('/') -and $IsWindows)) {
        throw "Destination '$declaredPath' is an absolute path for another platform."
    }
    return [IO.Path]::GetFullPath($Path)
}
