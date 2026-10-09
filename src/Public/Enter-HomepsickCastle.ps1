function Enter-HomepsickCastle {
    <# .SYNOPSIS Changes the current PowerShell location to a castle. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CastleName)

    $castle = Get-HomepsickCastle -CastleName $CastleName
    Set-Location -LiteralPath $castle.CastlePath
}
