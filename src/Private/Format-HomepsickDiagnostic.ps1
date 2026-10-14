function Format-HomepsickDiagnostic {
    param([object[]]$Diagnostic)
    foreach ($issue in $Diagnostic) {
        $entries = if ($issue.Entries.Count) { " $($issue.Entries -join ', ')" } else { '' }
        "[$($issue.Code)]${entries}: $($issue.Message)"
    }
}
