function Invoke-HomepsickGit {
    # Runs Git without shell evaluation and returns HomepsickGitResult
    # (ExitCode, Output, Error). Nonzero exits throw unless AllowFailure is set.
    # Optional UTF-8 stdin supports exact per-path Git index restoration.
    [CmdletBinding()]
    [OutputType([HomepsickGitResult])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure,
        [AllowEmptyString()][string]$InputText
    )

    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'git'
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $PSBoundParameters.ContainsKey('InputText')
    if ($start.RedirectStandardInput) { $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false) }
    $start.CreateNoWindow = $true
    $start.ArgumentList.Add('-C')
    $start.ArgumentList.Add($RepositoryPath)
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($start.RedirectStandardInput) {
            $process.StandardInput.Write($InputText)
            $process.StandardInput.Close()
        }
        $process.WaitForExit()
        $result = [HomepsickGitResult]@{
            ExitCode = $process.ExitCode
            Output   = $stdout.GetAwaiter().GetResult()
            Error    = $stderr.GetAwaiter().GetResult()
        }
        if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
            throw "git $($Arguments -join ' ') failed in '$RepositoryPath': $($result.Error.Trim()) $($result.Output.Trim())"
        }
        return $result
    }
    finally { $process.Dispose() }
}
