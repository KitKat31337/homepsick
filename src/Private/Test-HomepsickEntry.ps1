function Test-HomepsickEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LiteralPath)

    # Get-Item also finds a symbolic link whose target no longer exists.
    return ($null -ne (Get-Item -LiteralPath $LiteralPath -Force -ErrorAction SilentlyContinue))
}
