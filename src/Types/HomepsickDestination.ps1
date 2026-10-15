# Validated literal destination declaration; external writes still require runtime opt-in.
class HomepsickDestination {
    [string]$Path
    [bool]$OutsideHome
}
