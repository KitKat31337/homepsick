# Selection adds machine-specific decisions without changing the normalized root.
class HomepsickRootSelection : HomepsickManifestRoot {
    [bool]$Selected
    [string[]]$Reasons = @()
    [string]$DestinationPath
    [bool]$OutsideHome
}
