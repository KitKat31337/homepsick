function Test-GithubShorthand {
    # Returns whether text has the supported owner/repo GitHub shorthand form.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$stringToTest
    )
    return (($stringToTest -match "^([0-9A-Za-z-]+/[0-9A-Za-z_\.-]+)$") -and (-not ($stringToTest -match "\.git$")))
}
