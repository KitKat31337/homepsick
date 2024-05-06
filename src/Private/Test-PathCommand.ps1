function Test-PathCommand {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [string] $command
    )
    
    if ((Get-Command -Type Application -ErrorAction SilentlyContinue $command) -ne $null) 
    {
        return $true
    }
    else
    {
        return $false
    }
}
