function Get-HomePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    if ($env:HOME -ne $null) {
        return $env:HOME
    }
    else {
        return $env:USERPROFILE
    }
}