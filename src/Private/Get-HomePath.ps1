function Get-HomePath {
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
