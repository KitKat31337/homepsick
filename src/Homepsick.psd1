@{
    RootModule = 'Homepsick.psm1'
    ModuleVersion = '0.2.0'
    GUID = 'a479ed58-8796-4d5d-b4e8-47f8992380d7'
    Author = 'KitKat31337'
    Description = 'PowerShell castle management compatible with homeshick layouts.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Add-HomepsickFile',
        'Enable-HomepsickCastle',
        'Enter-HomepsickCastle',
        'Get-HomepsickCastle',
        'Get-HomepsickCastleStatus',
        'Invoke-HomepsickCastleRefresh',
        'New-HomepsickCastle',
        'Update-HomepsickCastle'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
