function Get-HomepsickCastle {
    <#
    .SYNOPSIS
    Gets an installed castle or lists all installed castles.
    .PARAMETER CastleName
    Name of one installed castle. Omit to list every installed castle.
    .OUTPUTS
    HomepsickCastle. Installed castle locations and operations.
    .EXAMPLE
    Get-HomepsickCastle -CastleName dotfiles
    Gets the installed dotfiles castle.
    #>
    [CmdletBinding()]
    [OutputType([HomepsickCastle])]
    param([string]$CastleName)

    if ($PSBoundParameters.ContainsKey('CastleName')) {
        $castle = [HomepsickCastle]::new($CastleName)
        if (-not $castle.Exists()) { throw "Castle '$CastleName' does not exist." }
        return $castle
    }

    foreach ($name in @(Get-HomepsickNames)) {
        [HomepsickCastle]::new($name)
    }
}
