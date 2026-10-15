# Load base and property types before the classes that reference them; alphabetical
# file enumeration cannot guarantee the dependency order of separate class files.
$typeFiles = @(
    'HomepsickClass.ps1'
    'HomepsickDiagnostic.ps1'
    'HomepsickDestination.ps1'
    'HomepsickManifestRoot.ps1'
    'HomepsickRootSelection.ps1'
    'HomepsickManifest.ps1'
    'HomepsickMachineFacts.ps1'
    'HomepsickMachineFactResult.ps1'
    'HomepsickLinkMapping.ps1'
    'HomepsickLinkCandidate.ps1'
    'HomepsickLinkPlan.ps1'
    'HomepsickTrackingPath.ps1'
    'HomepsickGitResult.ps1'
    'HomepsickManifestValidationResult.ps1'
    'HomepsickTrackedFile.ps1'
    'HomepsickRepositoryFile.ps1'
)
$Types = @($typeFiles | ForEach-Object {
    Get-Item -LiteralPath (Join-Path $PSScriptRoot "Types/$_") -ErrorAction Stop
})

#Get public and private function definition files.
    $Publics  = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue )
    $Privates = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue )

#Dot source the files
    Foreach($import in @($Types + $Publics + $Privates))
    {
        Try
        {
            . $import.fullname
        }
        Catch
        {
            Write-Error -Message "Failed to import function $($import.fullname): $_"
        }
    }

# Define the types to export with type accelerators.
$ExportableTypes =@(
    [HomepsickCastle]
)
# Get the internal TypeAccelerators class to use its static methods.
$TypeAcceleratorsClass = [psobject].Assembly.GetType(
    'System.Management.Automation.TypeAccelerators'
)
# Ensure none of the types would clobber an existing type accelerator.
# If a type accelerator with the same name exists, throw an exception.
$ExistingTypeAccelerators = $TypeAcceleratorsClass::Get
foreach ($Type in $ExportableTypes) {
    if ($Type.FullName -in $ExistingTypeAccelerators.Keys) {
        $Message = @(
            "Unable to register type accelerator '$($Type.FullName)'"
            'Accelerator already exists.'
        ) -join ' - '

        throw [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new($Message),
            'TypeAcceleratorAlreadyExists',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Type.FullName
        )
    }
}
# Add type accelerators for every exportable type.
foreach ($Type in $ExportableTypes) {
    $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    foreach($Type in $ExportableTypes) {
        $TypeAcceleratorsClass::Remove($Type.FullName)
    }
}.GetNewClosure()

Foreach ($public in $Publics)
{
    Export-ModuleMember -Function $public.Basename
}
