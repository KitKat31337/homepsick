# Structured validation or planning issue with the implicated root identifiers.
class HomepsickDiagnostic {
    [string]$Severity = 'Error'
    [string]$Code
    [string[]]$Entries = @()
    [string]$Message
}
