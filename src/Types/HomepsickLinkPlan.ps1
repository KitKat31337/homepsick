# Shared resolution result for preview, validation, tracking, and linking.
class HomepsickLinkPlan {
    [string]$RepositoryPath
    [bool]$HasManifest
    [HomepsickMachineFacts]$MachineFacts
    [string[]]$FactNotes = @()
    [HomepsickRootSelection[]]$Entries = @()
    [HomepsickLinkCandidate[]]$Candidates = @()
    [HomepsickLinkCandidate[]]$Winners = @()
    [HomepsickLinkMapping[]]$RootMappings = @()
    [HomepsickLinkCandidate[]]$Shadowed = @()
    [HomepsickLinkCandidate[]]$Ties = @()
    [HomepsickLinkCandidate[]]$Conflicts = @()
    [HomepsickDiagnostic[]]$Errors = @()
    [HomepsickDiagnostic[]]$Warnings = @()
    [bool]$IsValid
}
