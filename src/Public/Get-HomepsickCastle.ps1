function Get-HomepsickCastle
{
    [CmdletBinding()]
    [OutputType([HomepsickCastle[]])]
    param
    (
        [Parameter(Mandatory=$false)]
        [string]$CastleName
    )

    if ($CastleName)
    {
        $castle = [HomepsickCastle]::new($CastleName)
        if (-not ($castle.Exists()))
        {
            Throw "Castle $castleName does not exist."
        }
        return @($castle)
    }
    else
    {
        [HomepsickCastle[]] $castles = @()
        ((Get-ChildItem -Path (Get-HomepsickPath -Repos) -Directory) | Select-Object -ExpandProperty Name) | ForEach-Object -Process { $castles += [HomepsickCastle]::new($_) }
        return $castles
    }
}