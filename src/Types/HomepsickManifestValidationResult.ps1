# Public validation result preserving the command's existing property names.
class HomepsickManifestValidationResult {
    [string]$RepositoryPath
    [bool]$HasManifest
    [bool]$IsValid
    [HomepsickDiagnostic[]]$Errors = @()
    [HomepsickDiagnostic[]]$Warnings = @()
}
