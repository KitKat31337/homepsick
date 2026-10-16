# Configuration and defaults

[Documentation index](README.md#documentation) · [Command reference](commands.md)

## Configuration sources

homepsick has **no configuration file**, registry settings, JSON/YAML schema, or persistent preferences. Its behavior comes from command parameters, the home-directory resolver, the castle's Git index and Git's own configuration.

| Setting | Implemented behavior |
| --- | --- |
| Destination home | Nonblank `$env:HOME`; otherwise `[Environment]::GetFolderPath('UserProfile')` |
| Storage root | `<resolved-home>/.homesick` |
| Castle repositories | `<resolved-home>/.homesick/repos` |
| Link sources | Git-index entries under the literal, case-sensitive prefix `home/` |
| Default castle scope | All discovered castles for enable, status, update and refresh; one required castle for add and enter |
| Refresh interval | `-Days 7`; integer range 0–36500, inclusive |
| Clone/update linking | Prompt when applicable; `-Batch` suppresses the offer, `-Link` requests linking |
| Link conflicts | Prompt by default; `-Batch` or `-Skip` preserves them; `-Force` permits replacement; `-Skip` wins if combined with `-Force` |
| Routine output | `-Verbose` for per-file, skipped and fresh-castle messages |

The implementation is in [Get-HomePath](../src/Private/Get-HomePath.ps1), [Get-HomepsickPath](../src/Private/Get-HomepsickPath.ps1) and the [public commands](commands.md). Omitting `-CastleName` selects all discovered castles even if `-All` is omitted or explicitly false. `-All` and `-CastleName` belong to mutually exclusive parameter sets. There is no configurable default castle.

## Home and path overrides

`$env:HOME` is the only homepsick-specific path input. It changes **both** castle storage and link destinations for subsequent operations in the current process. There is no independent repository-root, destination-root, XDG or per-castle mapping override. A missing or whitespace-only value uses the .NET user-profile fallback; an invalid or relative value is not validated by a configuration loader and may produce path errors or unexpected relative paths. Use an absolute filesystem directory.

PowerShell's `$HOME` automatic variable and `$env:HOME` are different values. Examples using `$HOME` assume it names the homepsick destination. This usually holds with default environments; verify it if you override `HOME`, particularly on Windows. `$HOME` is not reassigned when you change `$env:HOME`.

For experiments, choose a temporary root and restore the environment afterward:

```powershell
$previousHome = $env:HOME
$sandboxHome = Join-Path ([IO.Path]::GetTempPath()) ('homepsick-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $sandboxHome | Out-Null
try {
    $env:HOME = $sandboxHome
    New-HomepsickCastle -CastleName trial
    Set-Content -LiteralPath (Join-Path $sandboxHome '.example') -Value 'example'
    Add-HomepsickFile -CastleName trial -Path (Join-Path $sandboxHome '.example')
    Get-HomepsickCastle
}
finally {
    $env:HOME = $previousHome
}
```

This changes the current process's environment, creates only temporary data, and leaves it for inspection. It does not persist a user or machine environment setting. On Unix, Git also consults `HOME` for configuration, so this experiment can change which Git identity, credentials and signing settings Git sees. Existing `HomepsickCastle` objects retain the paths calculated when constructed; obtain new objects after changing the home value. Do not switch homes during a multi-step operation.

## Git configuration and ignore rules

homepsick runs the installed Git executable without replacing its authentication, identity, signing, remote or pull configuration. Git's ordinary environment and configuration precedence apply. New castles receive `git init` with no forced initial branch, identity, remote or initial commit.

`Add-HomepsickFile` runs `git check-ignore --quiet -- home/<relative-path>` before moving an entry. Ignored paths are skipped with a warning. `Enable-HomepsickCastle` uses the index (`git ls-files --stage -z`): untracked files are ignored, staged new files are eligible before commit, and already tracked files remain eligible regardless of later ignore rules. There is no force-add option on `Add-HomepsickFile`.

`Update-HomepsickCastle` uses plain `git pull`, not a mandated rebase or fast-forward policy. Set your Git policy deliberately and inspect the working tree before pulling. Submodule initialization uses the URLs and commits in the castle, subject to Git's transport restrictions. Do not broadly weaken Git transport rules to bypass a failing submodule clone.

## Conditional configuration is absent

There are no environment filters, hostname/OS selectors, file groups, condition arrays, priority overrides, precedence scores, tie breakers, templates or fallback candidates. No condition schema is parsed. A tracked file named `home/.config/tool.windows` maps literally to `<home>/.config/tool.windows`; its suffix does not select Windows. A root-level `.homesickrc` or `.homesick_subdir` is not evaluated by homepsick.

Use explicit castle selection and distinct destinations for machine-specific configuration. Automatic all-castle operations include every discovered castle, so avoid those operations if you intend only a subset. [Cross-castle collisions](castles-and-linking.md#collisions-and-ordering) are resolved by ordinary link conflicts, not configuration precedence.
