# Configuration and defaults

[Documentation index](README.md#documentation) · [Command reference](commands.md)

## Configuration sources

homepsick has no global settings file, registry settings or persistent command preferences. Each castle may contain an optional versioned `homepsick.json` at its root. Behavior comes from command parameters, that manifest when present, the home-directory resolver, the castle's Git index and Git's own configuration. Castles without a manifest retain the ordinary `home/` workflow.

| Setting | Implemented behavior |
| --- | --- |
| Destination home | Nonblank `$env:HOME`; otherwise `[Environment]::GetFolderPath('UserProfile')` |
| Storage root | `<resolved-home>/.homesick` |
| Castle repositories | `<resolved-home>/.homesick/repos` |
| Link sources | Git-index entries under `home/`, or selected manifest roots; source prefixes are case-sensitive |
| Root selection | Implicit `home/` at priority 0; optional manifest conditions and per-castle file priorities |
| Default castle scope | All discovered castles for enable, status, update and refresh; one required castle for add and enter |
| Refresh interval | `-Days 7`; integer range 0–36500, inclusive |
| Clone/update linking | Prompt when applicable; `-Batch` suppresses the offer, `-Link` requests linking |
| Link conflicts | Prompt for individual file/link conflicts; `-Batch` or `-Skip` preserves them; `-Force` permits replacement; real directories remain intact |
| External destinations | Require manifest `outsideHome: true` and runtime `-AllowOutsideHome` before writes |
| Synthetic selection | `-MachineFacts` replaces detected facts on validate, plan, enable and add; paths/environment remain native |
| Routine output | `-Verbose` for per-file, skipped and fresh-castle messages |

The implementation is in [Get-HomePath](../src/Private/Get-HomePath.ps1), [Get-HomepsickPath](../src/Private/Get-HomepsickPath.ps1) and the [public commands](commands.md). Omitting `-CastleName` selects all discovered castles even if `-All` is omitted or explicitly false. `-All` and `-CastleName` belong to mutually exclusive parameter sets. There is no configurable default castle.

## Home and path overrides

`$env:HOME` changes **both** castle storage and the default home destination for subsequent operations in the current process. Storage remains fixed under that home; manifests can additionally declare named destinations. A missing or whitespace-only `HOME` uses the .NET user-profile fallback; an invalid or relative home value is not validated by a configuration loader and may produce path errors or unexpected relative paths. Use an absolute filesystem directory. PowerShell examples using `$HOME` assume it names the same directory.

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

`Add-HomepsickFile` runs `git check-ignore --quiet -- <source-relative-path>` before moving an entry. Without a manifest this path is under `home/`; with a manifest it follows the selected storage mapping. Initialized submodules use their own index. Ignored paths are skipped with a warning. `Enable-HomepsickCastle` uses the index (`git ls-files --stage -z`): untracked files are ignored, staged new files are eligible before commit, and already tracked files remain eligible regardless of later ignore rules. There is no force-add option on `Add-HomepsickFile`.

`Update-HomepsickCastle` uses plain `git pull`, not a mandated rebase or fast-forward policy. Set your Git policy deliberately and inspect the working tree before pulling. Submodule initialization uses the URLs and commits in the castle, subject to Git's transport restrictions. Do not broadly weaken Git transport rules to bypass a failing submodule clone.

## Manifest configuration

`homepsick.json` version 1 declares `roots` and optional named `destinations`. Existing `home/` is an implicit root at priority 0 unless configured explicitly. A manifest castle can omit `home/`. Conditions select OS, Linux distribution/lineage/version, Windows role/release/edition, and host. Different fields combine with AND; arrays within a field mean OR. Priorities add explicitly written fields, or an integer `priority` replaces the whole score. Equal highest-priority candidates for the same destination fail before linking; there is no manifest-order tie breaker.

Use [the manifest guide](manifests.md) for the complete schema, canonical values, priority table and examples. Inspect the shared plan before enabling a changed configuration:

```powershell
Test-HomepsickManifest -CastleName personal | Format-List IsValid, Errors, Warnings
$plan = Get-HomepsickLinkPlan -CastleName personal
$plan.Entries | Format-Table Entry, Source, Selected, Priority, Reasons -Wrap
$plan.Winners | Format-Table SourcePath, DestinationPath, Allowed, ExistingState
```

`Test-HomepsickManifest` returns structured diagnostics, not a boolean. `Get-HomepsickLinkPlan` reports facts, selection reasons, candidates, winners, shadowed files, ties and destination conflicts. Both are read only and accept `-RepositoryPath` for a repository outside installed castle storage. A missing source directory is a warning; a selected missing tracked file or unsafe source is an error.

### Destination paths and environment variables

Named destinations accept `~/relative/path`, POSIX absolute paths, Windows drive-absolute subdirectories, or one leading `%NAME%`, `$NAME`, or `${NAME}` process-environment variable with an optional directory suffix. For example, `%APPDATA%/../Local/Editor` expands the actual AppData value before normalizing parent navigation. Values must be absolute paths; missing/empty variables fail selected entries. Inactive and unused destinations do not read their variables. No shell, PowerShell expression, default substitution or recursive expansion is evaluated.

Windows drive destinations accept either separator style; JSON backslashes must be escaped. POSIX values require forward slashes, and a trailing backslash is rejected. Destination `.` and `..` navigation is lexical and bounded by its home or filesystem anchor. Sources, `into` and tracked relative filenames remain strict portable relative paths. UNC/device paths and filesystem roots remain invalid. See [destination environment syntax](manifests.md#environment-variables-in-destination-paths) for variable-name rules and platform eligibility.

The final resolved path determines whether it is outside home. Both `outsideHome: true` and `-AllowOutsideHome` are required to modify an external destination, including through clone, pull or refresh linking. `-WhatIf` is available on new, add, enable and update; refresh itself does not support it. `Get-HomepsickLinkPlan -AllowOutsideHome` only marks eligible external candidates as authorized in the preview.

### Selection scope and compatibility

`-MachineFacts` on validation, planning, enable or add replaces detection completely; omitted fields stay unavailable. It changes condition selection, not the executing filesystem or environment. Windows and Linux fact normalization can be inspected on either host, but selecting a foreign absolute destination still produces a path error. Windows-specific conditions and recognized AppData/profile variables require Windows even without `when.os`.

A filename suffix such as `tool.windows` has no selection meaning by itself. Root-level `.homesickrc` and `.homesick_subdir` are not evaluated. Manifests do not render configuration-file contents or execute scripts.

Automatic all-castle operations still include every discovered castle. Manifest priorities select candidates **within one castle**; [cross-castle collisions](castles-and-linking.md#collisions-and-ordering) use ordinary link conflicts, without global precedence. Use explicit castle selection or distinct destinations when appropriate.
