# Internal contracts shared by manifest validation, selection, planning, and execution.
# Raw JSON stays untyped until validated; these types represent normalized data.
# Public OutputType metadata uses names so callers need no additional type accelerators.
class HomepsickDiagnostic {
    [string]$Severity = 'Error'
    [string]$Code
    [string[]]$Entries = @()
    [string]$Message
}

class HomepsickDestination {
    [string]$Path
    [bool]$OutsideHome
}

class HomepsickManifestRoot {
    [string]$Entry
    [string]$Source
    [string]$Target
    [string]$Into
    [System.Collections.IDictionary]$When = @{}
    [int]$CalculatedPriority
    [bool]$PriorityOverridden
    [int]$Priority
    [bool]$Implicit
}

# Selection adds machine-specific decisions without changing the normalized root.
class HomepsickRootSelection : HomepsickManifestRoot {
    [bool]$Selected
    [string[]]$Reasons = @()
    [string]$DestinationPath
    [bool]$OutsideHome
}

class HomepsickManifest {
    [bool]$HasManifest
    [HomepsickManifestRoot[]]$Roots = @()
    [Collections.Generic.Dictionary[string, HomepsickDestination]]$Destinations =
        [Collections.Generic.Dictionary[string, HomepsickDestination]]::new([StringComparer]::OrdinalIgnoreCase)
    [HomepsickDiagnostic[]]$Errors = @()
    [HomepsickDiagnostic[]]$Warnings = @()
}

class HomepsickMachineFacts {
    # Unavailable scalar facts remain null. Construct from non-null values only:
    # assigning null to a typed string property would coerce it to an empty string.
    [string]$os
    [string]$host
    [string]$distro
    [string[]]$distroLike = @()
    [string]$distroVersion
    [string]$windowsRole
    [string]$windowsRelease
    [string]$windowsEdition
}

class HomepsickMachineFactResult {
    [HomepsickMachineFacts]$Facts
    [string[]]$Notes = @()
}

class HomepsickLinkMapping {
    [string]$SourcePath
    [string]$DestinationPath
}

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

class HomepsickTrackingPath {
    [string]$Entry
    [string]$SourcePath
    [string]$RelativePath
    [string]$RepositoryRelativePath
}

class HomepsickGitResult {
    [int]$ExitCode
    [string]$Output
    [string]$Error
}

class HomepsickManifestValidationResult {
    [string]$RepositoryPath
    [bool]$HasManifest
    [bool]$IsValid
    [HomepsickDiagnostic[]]$Errors = @()
    [HomepsickDiagnostic[]]$Warnings = @()
}

# Preserve the two-property result of legacy home-only enumeration. The planner
# requests the repository-relative path as well, including submodule prefixes.
class HomepsickTrackedFile {
    [string]$RelativePath
    [string]$SourcePath
}

class HomepsickRepositoryFile : HomepsickTrackedFile {
    [string]$RepositoryRelativePath
}
