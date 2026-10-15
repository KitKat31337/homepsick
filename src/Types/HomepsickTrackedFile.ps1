# Preserve the two-property result of legacy home-only enumeration. The planner
# requests the repository-relative path as well, including submodule prefixes.
class HomepsickTrackedFile {
    [string]$RelativePath
    [string]$SourcePath
}
