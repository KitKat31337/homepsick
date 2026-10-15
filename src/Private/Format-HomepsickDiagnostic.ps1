function Format-HomepsickDiagnostic {
    # Returns display strings retaining each diagnostic code and implicated entry IDs.
    param([HomepsickDiagnostic[]]$Diagnostic)
    foreach ($issue in $Diagnostic) {
        $entries = if ($issue.Entries.Count) { " $($issue.Entries -join ', ')" } else { '' }
        "[$($issue.Code)]${entries}: $($issue.Message)"
    }
}
