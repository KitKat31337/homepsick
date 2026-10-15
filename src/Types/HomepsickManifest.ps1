# Validated manifest declarations and diagnostics. Raw JSON stays untyped until validation.
class HomepsickManifest {
    [bool]$HasManifest
    [HomepsickManifestRoot[]]$Roots = @()
    [Collections.Generic.Dictionary[string, HomepsickDestination]]$Destinations =
        [Collections.Generic.Dictionary[string, HomepsickDestination]]::new([StringComparer]::OrdinalIgnoreCase)
    [HomepsickDiagnostic[]]$Errors = @()
    [HomepsickDiagnostic[]]$Warnings = @()
}
