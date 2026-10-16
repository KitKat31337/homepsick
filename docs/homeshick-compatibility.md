# Homeshick and homesick compatibility

[Documentation index](README.md#documentation) · [Castles and linking](castles-and-linking.md)

homepsick implements core castle workflows as a PowerShell module. Its compatibility claim is a shared repository layout and related workflows, not complete command or behavioral parity. Neither homeshick nor homesick is required to run it.

## Relationship and layout

[homesick](https://github.com/technicalpickles/homesick) is the Ruby tool that calls dotfile repositories castles. [homeshick](https://github.com/andsens/homeshick) provides a Bash implementation of Git-backed dotfile management. homepsick uses the same conventional `.homesick/repos/<castle>/home` layout. A repository with ordinary tracked files under `home/` is the simplest interoperable case.

homepsick links tracked non-dot names as well as dotfiles. It does not evaluate homesick's Ruby `.homesickrc` or interpret `.homesick_subdir`. Those root files are not runtime configuration for this module. Homesick's documented default directory-linking and optional subdirectory rules differ from homepsick's ordinary-directory traversal. See the [homesick README](https://github.com/technicalpickles/homesick#homesick) for that tool's own contract.

## Workflow equivalents

This table compares intentions, not interchangeable shell syntax. The authoritative homeshick references are its [command implementation/help](https://github.com/andsens/homeshick/blob/master/lib/commands/help.sh) and [command guide](https://github.com/andsens/homeshick/wiki/Commands).

| Homeshick workflow | homepsick equivalent |
| --- | --- |
| `homeshick generate CASTLE` | `New-HomepsickCastle -CastleName CASTLE` |
| `homeshick clone URI` | `New-HomepsickCastle -Clone -GitUrl URI` |
| `homeshick list` / `ls` | `Get-HomepsickCastle` |
| `homeshick link CASTLE` / `symlink CASTLE` | `Enable-HomepsickCastle -CastleName CASTLE` |
| `homeshick track CASTLE FILE` | `Add-HomepsickFile -CastleName CASTLE -Path FILE` |
| `homeshick check CASTLE` / `updates CASTLE` | `Get-HomepsickCastleStatus -CastleName CASTLE` |
| `homeshick pull CASTLE` | `Update-HomepsickCastle -CastleName CASTLE` |
| `homeshick refresh DAYS CASTLE` | `Invoke-HomepsickCastleRefresh -Days DAYS -CastleName CASTLE` |
| `homeshick cd CASTLE` | `Enter-HomepsickCastle -CastleName CASTLE` |
| `homeshick help TASK` | `Get-Help <PowerShell-command> -Full` |

homepsick does not export the short homeshick aliases or a dispatcher. Its commands take one castle name, except all-castle mode on enable/status/update/refresh; loop for a selected subset. Use named PowerShell arguments rather than copying homeshick argument positions.

## Meaningful differences

- **Linking:** both tools work with Git-tracked castle entries and can merge distinct files into shared home directories. homepsick's leaf traversal and conflict switches are described in [link semantics](castles-and-linking.md). Do not infer complete handling of directory symlinks from homeshick's more detailed [linking table](https://github.com/andsens/homeshick/wiki/Symlinking). In particular, homepsick cannot replace a blocking ancestor file automatically.
- **Replacement:** homepsick supports `-Skip`, `-Batch` and `-Force` on enable, with no backup for individual replacements. Real directory conflicts remain intact even under force. `Add-HomepsickFile` skips existing castle destinations and has no force option; homeshick's documented force behavior for track must not be assumed here. PowerShell `-WhatIf` exists on add, enable, new and update; refresh itself has no dry-run parameter.
- **Clone/pull:** homepsick offers interactive linking when applicable, including selected manifest roots without `home/`. `-Batch` suppresses the offer; `-Link -Batch` requests linking with conflict skipping. Ordinary castles retain the added/renamed `home/` diff gate; manifest castles also recognize manifest/selected-root modifications and deletions across a changed `HEAD`. Submodule update checks out recorded commits after pull, rather than independently pulling each submodule branch.
- **Status/refresh:** homepsick returns status objects instead of homeshick-style terminal status/exit-code conventions. It queries live remote heads without fetching, with [classification limits](commands.md#get-homepsickcastlestatus). Refresh uses `FETCH_HEAD` age and is only run on invocation. There is no imported shell startup automation.
- **Location:** homepsick enters the repository root. Homeshick's shell wrapper also enters the root in the [current `homeshick.sh` implementation](https://github.com/andsens/homeshick/blob/master/homeshick.sh); some homeshick prose says `home/`, so check the wrapper you actually use.
- **Platforms:** homeshick's documented runtime is Bash and Git; homepsick's is PowerShell 7.4+ and Git. Windows/Linux CI coverage and unverified macOS behavior are described in [platform support](platforms-and-troubleshooting.md#what-is-tested). Shared source data can still contain OS-specific filenames, symlinks and application paths.

There is no homepsick unlink, castle removal, commit, push, arbitrary-command runner, editor integration or homesick `rc` command. Use Git directly for commit/push and deliberate filesystem operations for retirement. This is a statement about homepsick's implemented feature set, not a claim that every absent feature is provided by homeshick.

## Homepsick manifest extension

Optional `homepsick.json` is a Homepsick-specific versioned schema, not an interpretation of another manager's configuration files. It selects source roots using OS/distribution, Windows product or host facts, resolves within-castle file priorities, and maps settings to home or named destinations. It does not establish global precedence between castles. See [configuration](configuration.md#manifest-configuration) and [the complete manifest guide](manifests.md).

`Test-HomepsickManifest` and `Get-HomepsickLinkPlan` validate and preview this extension. Manifest tracking can store files in additional roots, with `-Root` for ambiguous choices. External paths require both explicit declaration and runtime opt-in. Destination environment variables and `.`/`..` are processed as path data, without shell execution or rendering file contents.

## Sharing castles between tools

Both tools can read a compatible castle working tree in the shared storage location. Review the inventory and `git status` before switching tools. Avoid concurrent Git mutations or conflicting link operations. Different conflict policies, directory-link handling, relative symlinks and case behavior can produce different results; configuration files for another manager are not honored by homepsick.

Use one deliberate link manager at a time, prefer ordinary directories with tracked files, and avoid overlapping destinations across castles. Other managers must not be assumed to understand Homepsick's manifests, overlays or external mappings. Keeping a conventional `home/` baseline makes that portion usable by tools following the ordinary layout. Renamed/deleted files may require manual stale-link cleanup in homepsick. Sharing a layout does not make every link or external tool configuration portable.

The comparison was checked against upstream README, help, shell wrapper and wiki sources on 2026-10-14. No homeshick/homesick interoperability execution was performed during this task; the comparison is based on source and documentation inspection.
