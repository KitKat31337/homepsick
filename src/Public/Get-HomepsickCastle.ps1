function Get-HomepsickCastle {
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
