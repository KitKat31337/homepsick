function Update-HomepsickCastle {
    [CmdletBinding(DefaultParameterSetName = 'NoParams')]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'ByCastleName')]
        [string]$CastleName,
        [Parameter(Mandatory = $false, ParameterSetName = 'All')]
        [switch]$All
    )

    if ($CastleName) {
        $castle = Get-HomepsickCastle -CastleName $CastleName
        $castle.Update()
    }
    else {
        $castles = Get-HomepsickCastle
        $castles | ForEach-Object {
            $castle = $_
            $castle.Update()
        }
    }
}