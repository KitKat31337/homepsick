function Get-HomepsickPath {
    [CmdletBinding(DefaultParameterSetName="None")]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$false, ParameterSetName="Repos")]
        [switch]$Repos,
        [Parameter(Mandatory=$false, ParameterSetName="Root")]
        [switch]$Root
    )

    if ($Repos)
    {
        return [IO.Path]::Combine((Get-HomePath), '.homesick', 'repos')
    }
    else # Root
    {
        return [IO.Path]::Combine((Get-HomePath), '.homesick')
    }
}