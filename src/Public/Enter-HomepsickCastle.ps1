function Enter-HomepsickCastle {
    <#
    .SYNOPSIS
    Changes the current PowerShell location to a castle.
    .PARAMETER CastleName
    Name of the installed castle to enter.
    .EXAMPLE
    Enter-HomepsickCastle -CastleName dotfiles
    Changes the current location to the dotfiles repository.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CastleName)

    $castle = Get-HomepsickCastle -CastleName $CastleName
    Set-Location -LiteralPath $castle.CastlePath
}
