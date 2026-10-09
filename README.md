# Homepsick

A PowerShell implementation of [homeshick](https://github.com/andsens/homeshick), using the same `$HOME/.homesick/repos/<castle>/home` layout. Requires PowerShell 7.4 or later and Git. Developed on Windows and tested on Windows and Linux in CI.

```powershell
git clone https://github.com/KitKat31337/homepsick.git
Import-Module ./homepsick/src/Homepsick.psd1
```

| Homeshick task | PowerShell command |
| --- | --- |
| `generate CASTLE` | `New-HomepsickCastle -CastleName CASTLE` |
| `clone URI` | `New-HomepsickCastle -Clone -GitUrl URI` |
| `list` | `Get-HomepsickCastle` |
| `link CASTLE` | `Enable-HomepsickCastle -CastleName CASTLE` |
| `pull CASTLE` | `Update-HomepsickCastle -CastleName CASTLE` |
| `check CASTLE` | `Get-HomepsickCastleStatus -CastleName CASTLE` |
| `refresh DAYS CASTLE` | `Invoke-HomepsickCastleRefresh -Days DAYS -CastleName CASTLE` |
| `track CASTLE FILE` | `Add-HomepsickFile -CastleName CASTLE -Path FILE` |
| `cd CASTLE` | `Enter-HomepsickCastle -CastleName CASTLE` |

Omit `-CastleName` on link, pull, check, or refresh to process every installed castle. Clone accepts a Git URL, local path, or GitHub `owner/repo` shorthand. By default, clone and pull offer to link files interactively. `-Batch` suppresses prompts; combine it with `-Link` to link automatically. Refresh checks Git's `FETCH_HEAD` timestamp and defaults to seven days; `-Pull` performs the pull without prompting.

Linking acts on Git-tracked files under a castle's `home` directory, including initialized submodules. Existing paths prompt before replacement. `-Skip` skips conflicts, `-Batch` defaults to skipping them, and `-Force` replaces them. All file-changing commands support PowerShell's `-WhatIf` where appropriate. Use `-Verbose` to show routine per-file status. Windows symbolic links require an account or configuration permitted to create them, such as Developer Mode or an elevated session.

```powershell
New-HomepsickCastle -CastleName my-dotfiles
Add-HomepsickFile -CastleName my-dotfiles -Path "$HOME/.gitconfig"
Get-HomepsickCastleStatus
Update-HomepsickCastle -Link -Batch
```

Run the Pester 5+ suite with:

```powershell
Invoke-Pester ./tests
```
