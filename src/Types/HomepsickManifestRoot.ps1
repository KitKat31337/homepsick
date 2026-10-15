# Normalized source-to-destination declaration before machine-specific selection.
class HomepsickManifestRoot {
    [string]$Entry
    [string]$Source
    [string]$Target
    [string]$Into
    [System.Collections.IDictionary]$When = @{}
    [string[]]$DestinationOS = @()
    [int]$CalculatedPriority
    [bool]$PriorityOverridden
    [int]$Priority
    [bool]$Implicit
}
