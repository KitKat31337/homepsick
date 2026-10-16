function Get-HomePath {
    # Returns the configured home path, honoring HOME before the user-profile fallback.
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    if (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
        return $env:HOME
    }
    else {
        return [Environment]::GetFolderPath('UserProfile')
    }
}
