# Tracked source candidate with its priority, resolution, and existing destination state.
class HomepsickLinkCandidate {
    [string]$Entry
    [string]$SourcePath
    [string]$RepositoryRelativePath
    [string]$RelativePath
    [string]$DestinationPath
    [string]$Target
    [int]$Priority
    [int]$CalculatedPriority
    [bool]$PriorityOverridden
    [bool]$OutsideHome
    [bool]$Allowed
    [string]$Status
    [string]$ExistingState
    [string]$Reason
}
