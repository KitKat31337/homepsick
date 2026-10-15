# Manifest roots and destinations

A castle can optionally place `homepsick.json` at its repository root. Castles without this file retain the ordinary homeshick layout and command usage, including home-file tracking. Only Git-tracked files are linked, including files in initialized submodules. Untracked files are never candidates. For every castle, directory conflicts remain for review; `-Force` replaces individual files or symbolic links and never recursively deletes a directory tree.

An existing `home/` directory is an implicit root targeting your home at priority 0. Declaring `source: "home"` explicitly replaces that implicit entry, so its files are processed only through the explicit declaration. Multiple explicit entries for the same source are allowed, for example to map shared settings differently on Windows and Linux. A manifest castle can omit `home/` entirely.

`Add-HomepsickFile` uses applicable manifest mappings to track destination files into source roots, including castles without `home/` and explicitly authorized external destinations. Multiple applicable mappings produce `AmbiguousTrackingRoot` regardless of priority: `-Root` chooses where the new file is stored. See [Track files into roots](#track-files-into-roots) for selection and rollback details. Without a manifest it continues to track home files into `home/`.

## Schema version 1

```json
{
  "version": 1,
  "destinations": {
    "systemConfig": {
      "path": "/etc/example",
      "outsideHome": true
    }
  },
  "roots": [
    { "source": "home_windows", "target": "home", "when": { "os": "windows" } },
    { "source": "home_linux", "target": "home", "when": { "os": "linux" } },
    { "source": "home_debian_like", "target": "home", "when": { "distroLike": "debian" } },
    { "source": "home_ubuntu", "target": "home", "when": { "distro": "ubuntu" } },
    {
      "source": "home_ubuntu_2404",
      "target": "home",
      "when": { "distro": "ubuntu", "distroVersion": "24.04" }
    },
    { "source": "home_windows_server", "target": "home", "when": { "windowsRole": "server" } },
    { "source": "home_windows_11", "target": "home", "when": { "windowsRelease": "11" } },
    {
      "source": "home_windows_11_pro",
      "target": "home",
      "when": { "windowsRelease": "11", "windowsEdition": "pro" }
    },
    {
      "source": "home_server_2022_datacenter",
      "target": "home",
      "when": { "windowsRelease": "server-2022", "windowsEdition": "datacenter" }
    },
    { "source": "home_machine1", "target": "home", "when": { "host": "machine1" } },
    {
      "source": "editor_settings",
      "target": "home",
      "into": "AppData/Roaming/Editor",
      "when": { "os": "windows" }
    },
    {
      "source": "editor_settings",
      "target": "home",
      "into": ".config/editor",
      "when": { "os": "linux" }
    },
    { "source": "system_config", "target": "systemConfig", "when": { "os": "linux" } }
  ]
}
```

The top-level object requires integer `version: 1` and a `roots` array. `destinations` is optional. Each root requires `source` and `target`; `into`, `when`, and `priority` are optional. An empty `when` or an omitted `when` matches every machine. Unknown properties, duplicate JSON properties, and malformed declarations are errors.

| Property | Meaning |
| --- | --- |
| `source` | Directory relative to the castle root. Nested roots are supported, but one declared source must not contain another; this includes implicit `home/`. |
| `target` | `home`, or a key declared in `destinations`. The name `home` is reserved. |
| `into` | Optional directory below the target. `editor_settings/settings.json` with `into: ".config/editor"` links to `$HOME/.config/editor/settings.json`. |
| `when` | Object containing the supported condition fields below. |
| `priority` | Optional signed 32-bit JSON integer replacing the entire default score. Negative values are permitted. |
| Destination `path` | `~/relative/path`, POSIX `/absolute/path`, Windows drive-absolute subdirectory using either slash style, or one leading environment variable with an optional directory suffix. |
| Destination `outsideHome` | Boolean explicitly authorizing an outside-home destination declaration; runtime authorization is also required. |

Use forward slashes in `source`, `into`, and home-relative destinations. Windows drive-absolute destinations accept either slash style, including `C:\config`, `D:/config`, and mixed Windows separators. In JSON, escape backslashes: write `"path": "C:\\config"`. Homepsick normalizes destination paths internally without rewriting the manifest. `~/` denotes the home directory Homepsick already uses (`HOME`, or the user profile when `HOME` is unset). Environment-variable forms are described below. No PowerShell expressions, shell commands, or wildcard expansion are evaluated. Spaces are supported. Paths outside the current home require `outsideHome: true`; prefer `~/` for portable locations within home.

A drive-absolute destination makes each root targeting it Windows-only even without `when.os`. Linux skips these entries without needing the drive, destination directory, or source directory to exist; a missing source can still produce a warning. Explicit conditions contradicting the inferred requirement, such as `os: linux` or `distro: ubuntu`, produce `UnreachableEntry` with the root identifier. The inferred platform requirement adds no priority points. POSIX absolute destinations only resolve on Unix; condition their roots explicitly when sharing a manifest with Windows. A foreign-platform absolute declaration still requires `outsideHome: true`.

Source and `into` paths must be relative and cannot contain `.` or `..`; tracked relative filenames retain that restriction too. Destination `path` values allow lexical `.` and `..` navigation: `~/AppData/Roaming/../Local/Editor` becomes `~/AppData/Local/Editor`, and `/etc/example/../other` becomes `/etc/other`. Navigation cannot move above the `~/` home anchor or a filesystem/drive root. Destinations resolving to a bare anchor, such as `D:/config/..`, are rejected. Normalization does not follow symlinks; existing safety checks apply to the resulting path before any writes.

All ordinary path components are validated before cancellation: `C:/config/.git/../settings` remains invalid. Empty components, `.git`, control characters, wildcards, Windows-invalid punctuation, trailing dots/spaces, and reserved Windows device names are forbidden. Backslashes remain invalid in `source`, `into`, home-relative/POSIX destinations, and tracked relative filenames. Drive-relative paths (`C:config`), UNC and device paths, and filesystem/drive roots (`/`, `C:/`, `D:\`) are rejected. Ordinary castles without manifests retain their existing filename rules.

A manifest can contain both Windows and POSIX destinations even when those paths, drives, or inactive source directories are absent. For example:

```json
{
  "version": 1,
  "destinations": {
    "windowsConfig": { "path": "C:\\ProgramData\\Example Editor", "outsideHome": true },
    "linuxConfig": { "path": "/etc/example-editor", "outsideHome": true }
  },
  "roots": [
    { "source": "editor_settings", "target": "windowsConfig" },
    { "source": "editor_settings", "target": "linuxConfig", "when": { "os": "linux" } }
  ]
}
```

On Linux, the Windows destination is implicitly inactive and does not prevent validation or linking Linux files. On Windows, the Linux entry's condition keeps it inactive. A missing native destination is valid and is created during linking only with the required outside-home opt-in. Synthetic `-MachineFacts` changes condition selection, not the executing filesystem's path rules: selecting Windows facts on Linux can select a drive destination for inspection, but the plan then reports `InvalidDestination` and linking stops before modifying files. Inactive declarations still undergo syntax validation, including the restrictions on anchor escapes, UNC/device paths, and drive roots.

### Environment variables in destination paths

A destination may start with one process-environment variable, using any of these forms on either platform:

| Form | Example |
| --- | --- |
| `%NAME%` | `%APPDATA%/../Local/Editor` |
| `$NAME` | `$XDG_CONFIG_HOME/editor` |
| `${NAME}` | `${HOME}/.config/editor` |

The variable may stand alone or have a directory suffix. `$NAME` and `${NAME}` use shell identifier names (`[A-Za-z_][A-Za-z0-9_]*`); `%NAME%` additionally supports names such as `%ProgramFiles(x86)%`. Names are looked up directly, with Windows case-insensitive and Unix case-sensitive environment behavior. `%HOME%` and `$HOME` read the actual environment variable; only `~/` uses Homepsick's home-directory fallback. These forms do not enable Bash or PowerShell evaluation. `$env:NAME`, defaults such as `${NAME:-fallback}`, multiple variable substitutions, and command substitution are unsupported. Values are literal data and are not expanded recursively.

```json
{
  "version": 1,
  "destinations": {
    "localEditor": { "path": "%APPDATA%/../Local/Editor", "outsideHome": true },
    "xdgEditor": { "path": "${XDG_CONFIG_HOME}/editor", "outsideHome": true }
  },
  "roots": [
    { "source": "editor_settings", "target": "localEditor" },
    { "source": "editor_settings", "target": "xdgEditor", "when": { "os": "linux" } }
  ]
}
```

`APPDATA`, `LOCALAPPDATA`, and `USERPROFILE` imply Windows eligibility in all three forms, without adding priority points. Other variable names do not imply an OS: use explicit conditions when a variable is available only on particular machines. A missing `XDG_CONFIG_HOME` does not fall back to `~/.config`; use `~/.config/editor` when that is the desired fixed location.

Unused destinations and skipped entries do not require their variables to exist. Static validation checks syntax without reading values; it retains conservative overlap warnings for environment destinations. Selected targets expand their variable and then normalize `.` and `..`. A missing/empty variable, relative value, foreign-platform value, or invalid final path produces `InvalidDestination` with the affected root identifier before linking. Environment values must be absolute paths. Windows values accept either separator style, including backslashes in the suffix; POSIX values and their suffixes require forward slashes.

The expanded, normalized path determines containment and conflicts. A result outside home requires both `outsideHome: true` and runtime `-AllowOutsideHome`; neither the variable nor `..` bypasses authorization. Symbolic-link parents, repository/storage destinations, filesystem roots, and other existing safeguards remain enforced. Preview, linking, and tracking use the same expansion and resolution.

## Conditions and detection

Different fields combine with AND. A string array within a field combines with OR; `"os": ["linux"]` has exactly the same match and score as `"os": "linux"`. Arrays must contain at least one distinct, nonempty string. Conditions and detected identifiers are trimmed and compared case-insensitively; plans show normalized lowercase facts. Numeric-looking releases must still be JSON strings.

| Field | Values and source |
| --- | --- |
| `os` | `windows`, `linux`, `macos`, or `freebsd`, detected from PowerShell's platform flags. |
| `distroLike` | Any lineage in Linux `ID_LIKE`, such as `debian`, `rhel`, or `fedora`. All space-separated lineages are retained. This does not infer a lineage from `ID`. |
| `distro` | Exact Linux `ID`, such as `ubuntu`, `debian`, or `fedora`. |
| `distroVersion` | Exact Linux `VERSION_ID`, such as `"24.04"`. |
| `windowsRole` | `workstation` or `server`. CIM `Win32_OperatingSystem.ProductType` 1 is workstation; 2 (domain controller) and 3 are server. |
| `windowsRelease` | `"10"`, `"11"`, `"server-2016"`, `"server-2019"`, `"server-2022"`, or `"server-2025"` are detected. Numeric future workstation names and `server-YYYY`/`server-YYYY-r2` remain valid declarations even when detection cannot recognize them. |
| `windowsEdition` | `home`, `pro`, `enterprise`, `education`, `standard`, or `datacenter`, normalized from CIM's language-independent `OperatingSystemSKU`. N, Core, evaluation, subscription, and Pro workstation variants are grouped into their edition families. Unknown SKUs remain unavailable. |
| `host` | Full machine name returned by .NET `Environment.MachineName`, lowercased; no DNS or short-name inference. |

Linux detection reads `/etc/os-release`, falling back to `/usr/lib/os-release`. It parses the identifiers as data, without sourcing the file. Linux-specific fields only match Linux. Windows-specific fields only match Windows. You can write `"distro": "ubuntu"` or `"windowsRelease": "11"` without an `os` field; platform requirements inferred during matching do not contribute priority.

Windows role, release, and edition are independent. Release detection uses numeric CIM product type and explicitly recognized build families, independently of localized `Caption` or product-name text. Workstation build families 10240, 10586, 14393, 15063, 16299, 17134, 17763, 18362, 18363, and 19041–19045 map to Windows 10; 22000, 22621, 22631, 26100, 26200, and 28000 map to Windows 11. Server families 14393/17763/20348/26100 map to 2016/2019/2022/2025, separately from workstation builds. Product type distinguishes workstation (1) from server (2 or 3); numeric SKU determines edition.

A newly introduced build family or SKU must be added to Homepsick's normalization tables before its release or edition becomes available. Homepsick does not guess a future release from an unbounded build range. An unknown fact stays unavailable without invalidating the manifest, while independently recognized facts can still match. `FactNotes` identifies unavailable Windows fields and includes the raw `ProductType`, `BuildNumber`, and `OperatingSystemSKU` for diagnosis; acquisition failures also appear there. Conditions requiring unavailable facts are skipped with an explanation in `Entries.Reasons`.

The product facts and edition mapping follow Microsoft's [CIM documentation](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem), [Windows SDK SKU definitions](https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/um/winnt.h), and [workstation](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information) and [Server release information](https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info).

## Priority within a castle

Add the score for every condition field **explicitly written** in an entry:

| Condition tier | String or singleton array | Array with two or more values |
| --- | ---: | ---: |
| `os` | 100 | 50 |
| `distroLike`, `windowsRole` | 1,000 per field | 500 per field |
| `distro`, `distroVersion`, `windowsRelease`, `windowsEdition` | 10,000 per field | 5,000 per field |
| `host` | 100,000 | 50,000 |

Implicit `home/` scores 0. Ubuntu alone scores 10,000; Ubuntu and `"24.04"` score 20,000. Windows 11 alone scores 10,000; Pro alone also scores 10,000; Windows 11 and Pro together score 20,000. `host: "machine1"` and `os: "windows"` score 100,100. `host: ["machine1", "machine2"]` scores 50,000. A matching multi-value array scores once per field, even when several `ID_LIKE` values match.

For each destination file, the highest-priority candidate wins. Lower-priority candidates are reported as shadowed. Equal highest priorities are errors before any files from that castle are linked, regardless of manifest order or Git enumeration order. A higher-priority combined overlay can resolve a lower-priority release/edition tie. A file destination that would contain another file destination is also an error, even when their priorities differ. Comparison follows the executing platform's path rules.

An explicit `priority` replaces the entire calculated score, rather than adding to it:

```json
{ "source": "home_special", "target": "home", "when": { "os": "windows" }, "priority": 75000 }
```

This entry scores 75,000, between a host array (50,000) and a single host (100,000). For complex custom ordering, assign explicit priorities to all competing entries. Priority never changes precedence between different castles. File and symbolic-link conflicts use the existing prompt, `-Skip`, `-Batch`, and `-Force` controls; directory conflicts are always left intact.

## Validate and preview

```powershell
$validation = Test-HomepsickManifest -CastleName dotfiles
$validation.IsValid
$validation.Errors | Format-Table Code, Entries, Message -Wrap
$validation.Warnings | Format-Table Code, Entries, Message -Wrap

$plan = Get-HomepsickLinkPlan -CastleName dotfiles
$plan.MachineFacts
$plan.FactNotes
$plan.Entries | Format-Table Entry, Source, Selected, Priority, Reasons -Wrap
$plan.Candidates | Format-Table Entry, SourcePath, DestinationPath, Priority, Status, ExistingState, Reason -Wrap
$plan.Winners
$plan.Shadowed
$plan.Ties
$plan.Conflicts
```

Both commands are read only and also accept `-RepositoryPath /path/to/castle` instead of `-CastleName`. Validation returns structured `Errors` and `Warnings`, each with a code, message, and involved entry identifiers such as `roots[2]`. It checks schema, paths, platform compatibility, overlapping sources, and current-machine file ties. Identical root declarations are `DuplicateRoot` errors even without files; condition property/value order and scalar versus singleton arrays do not make declarations distinct. Mutually exclusive entries reusing a source remain valid. Missing sources are warnings, as are declared existing sources with no tracked linkable files (`NoTrackedFiles`). Potential equal-priority overlaps remain warnings in validation and preview even when files are absent or entries do not match this machine. Linking reports current-plan errors with codes and entry identifiers, and omits the static `PotentialTie` warnings when executing an unambiguous plan. A structurally valid manifest can still have ordinary destination conflicts; inspect the plan before linking. Validate synthetic contexts for other machines too.

```powershell
$facts = @{
    os = 'windows'
    host = 'machine1'
    windowsRole = 'workstation'
    windowsRelease = '11'
    windowsEdition = 'pro'
}
Get-HomepsickLinkPlan -CastleName dotfiles -MachineFacts $facts
Test-HomepsickManifest -CastleName dotfiles -MachineFacts $facts

Get-HomepsickLinkPlan -CastleName dotfiles -MachineFacts @{
    os = 'linux'; host = 'machine1'; distro = 'ubuntu'
    distroVersion = '24.04'; distroLike = @('debian', 'linux')
}
```

`-MachineFacts` replaces detection completely: unspecified fields are unavailable. Fields from another OS are discarded. It changes condition evaluation, while paths still resolve using the executing OS and current user's home. `Enable-HomepsickCastle` and `Add-HomepsickFile` also accept this parameter to execute the same synthetic selection deliberately. Tests inject raw Linux and Windows detection contexts into the internal detector on both CI platforms; they do not rely on the CI host to exercise the other OS. Windows release/edition normalization tests use synthetic CIM facts rather than asserting the CI host's product identity.

## Track files into roots

```powershell
Add-HomepsickFile -CastleName dotfiles -Path "$HOME/.config/editor/settings.json" -Root editor_settings -WhatIf
Add-HomepsickFile -CastleName dotfiles -Path "$HOME/.config/editor/settings.json" -Root editor_settings
Add-HomepsickFile -CastleName dotfiles -Path /etc/example/settings.conf -Root system_config -AllowOutsideHome
```

Tracking reverses the applicable destination and `into` mapping to obtain the source-relative filename, moves the file into that root, stages it in Git, and links its original location back through the shared link plan. Directories are processed file by file, preserving relative paths. Files inside initialized submodules are staged in the submodule's own index; Homepsick does not commit the submodule or change its parent pointer. Ignore rules and existing source files retain their usual skip behavior.

If several mappings qualify, tracking reports `AmbiguousTrackingRoot` and requires `-Root`, regardless of priority. Choose a source directory, such as `home_linux`, or the entry identifier shown in the plan, such as `-Root 'roots[2]'`. A source-directory choice must identify one applicable entry for that file; use an entry identifier when shared-source mappings still leave several choices. An implicit `home/` and an active overlay targeting home can both qualify. Inactive roots cannot be selected to bypass their conditions.

`-Root` chooses where to store the file, without changing link priority. If another root already supplies a higher-priority file at that destination, the saved file is staged in the chosen root and the link-back points to the plan's winner. Tracking does not broadly link or clean other destinations. External files require the destination's `outsideHome: true` declaration and `-AllowOutsideHome`, just as linking does.

Tracking checks source and destination parents, portable relative paths, and castle-storage protection before moving files. Manifest source symbolic links must satisfy the same internal-file rules as linking. A failed move preserves the input; a failure during staging, validation, or link creation restores the original file or link and its prior Git index entry while preserving unrelated staged work. `-WhatIf` does not move, stage, or create source directories. `Get-Help Add-HomepsickFile -Full` describes the parameters and an example.

## Linking and external destinations

```powershell
Enable-HomepsickCastle -CastleName dotfiles -WhatIf
Enable-HomepsickCastle -CastleName dotfiles -Batch
Get-HomepsickLinkPlan -CastleName dotfiles -AllowOutsideHome
Enable-HomepsickCastle -CastleName dotfiles -AllowOutsideHome -WhatIf
Enable-HomepsickCastle -CastleName dotfiles -AllowOutsideHome -Batch
```

Preview and linking share the same root selection and file resolution. A selected outside-home file is reported with `OutsideHome: true` and `Allowed: false` unless `-AllowOutsideHome` is supplied. Linking skips it with a warning without runtime opt in. `-AllowOutsideHome` is also forwarded by clone, pull, and refresh. It grants no operating-system permissions; use an appropriately permitted account for locations such as `/etc/example`.

Existing symbolic links can be updated when a different root wins and their current target satisfies a currently declared source-to-destination mapping, including an entry inactive on this machine. An inactive environment-based mapping is available for this check only when an active entry resolves the same named destination; otherwise its variable stays unread and ownership cannot be established from that mapping. Homepsick infers managed ownership from that current relationship; it stores no ownership history. A manually created link satisfying the same check is indistinguishable from one Homepsick created. A removed overlay file can therefore fall back to another tracked file. Links merely pointing somewhere in the repository without the matching destination relationship are conflicts. Without a replacement winner, stale links are retained; broader cleanup is tracked in [#20](https://github.com/KitKat31337/homepsick/issues/20).

After outside-home opt in, conflicts follow the same policy inside and outside home. Verified managed links can be updated when the winner changes. Other individual files or symbolic links require confirmation or deliberate `-Force`; `-Batch` skips them unless combined with `-Force`, and `-Skip` always leaves them untouched. `-WhatIf` previews replacements without writing. Directory trees are never replaced, even with `-Force`, and are reported as conflicts for review. Removing a directory symbolic link leaves its target directory intact. Manifest source directories and destination parents cannot be symbolic links or reparse points; tracked symbolic source files must resolve to existing files inside the castle. Destinations within the source repository or Homepsick's storage are rejected. Parent paths and managed-link ownership are checked again during linking.

Clone offers its initial link prompt for selected manifest content even when there is no `home/`. Pull rechecks the link workflow when the manifest changes or tracked content in a selected root changes, including modifications, deletions, and submodule pointer updates. Skipped-root changes alone do not prompt. `-Batch` and `-Link` retain their existing roles. `Update-HomepsickCastle -WhatIf` previews the pull without changing Git or destinations.
