# Validated destination declaration; environment values resolve only for active targets.
class HomepsickDestination {
    [string]$Path
    [string]$EnvironmentVariable
    [string]$EnvironmentSuffix
    [bool]$OutsideHome
}
