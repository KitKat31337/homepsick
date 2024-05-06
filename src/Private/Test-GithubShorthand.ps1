function Test-GithubShorthand {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$stringToTest
    )
    return (($stringToTest -match "^([0-9A-Za-z-]+/[0-9A-Za-z_\.-]+)$") -and (-not ($stringToTest -match "\.git$")))
}
