# Normalized machine facts shared by root selection and plan inspection.
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
