function Resolve-HomepsickDestination {
    # Returns an absolute native path from a validated literal destination.
    # Only ~/ expands; reject foreign absolute syntax rather than interpreting
    # it as a local relative path. Never evaluate manifest text as code.
    param([string]$Path, [string]$HomePath)
    if ($Path.StartsWith('~/')) { return [IO.Path]::GetFullPath([IO.Path]::Combine($HomePath, $Path.Substring(2))) }
    if (($Path -match '^[A-Za-z]:/' -and -not $IsWindows) -or ($Path.StartsWith('/') -and $IsWindows)) {
        throw "Destination '$Path' is an absolute path for another platform."
    }
    return [IO.Path]::GetFullPath($Path)
}
