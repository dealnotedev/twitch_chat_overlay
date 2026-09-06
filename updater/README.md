# Twitch Chat Overlay Updater

Separate Flutter / Dart Windows application, implemented from scratch.
`updater/overlay_updater.exe` ships with its own Flutter engine and `data/`.
It requires no Dart, Flutter or .NET installation on the user's computer.

The UI supports Ukrainian and English through Flutter gen_l10n and ARB catalogs
in `lib/l10n/`. The overlay passes its active locale with `--locale uk` or
`--locale en`. The updater launches the overlay without locale arguments.
Standalone launches use the system language, falling back to English for unsupported locales.
Release notes retain the language used by the release author. The updater uses
the latest stable release of `dealnotedev/twitch_chat_overlay` on GitHub.

## User flow

Open **Перевірити оновлення…** in the overlay tray, or run
`updater/overlay_updater.exe`. It shows installed/latest versions, release notes
and download size. Release notes render Markdown with selectable text, headings,
lists, links, code blocks, quotes and tables. Web links open in the default browser.
Start the update with **Оновити оверлей**.

Chat continues running during download and verification. Before replacement, the
updater asks the matching overlay process to save its layout and exit. After
installation, **Відкрити оверлей** starts the app again.

Closing cancels checking/downloading; closing is blocked only during the
installation and recovery steps. Errors allow retrying. No background service,
scheduled task, administrator rights or GitHub token is required. Keep the app
in a user-writable folder.

## Build and distribute

Requirements: Flutter Windows toolchain. GitHub CLI is needed only for publishing.

```powershell
# Build both applications, run tests and create local release packages:
./tool/build_release.ps1

# After committing and pushing:
./tool/build_release.ps1 -Publish

# Optional custom release notes:
./tool/build_release.ps1 -Publish -NotesFile ./release-notes.md
```

Increment the semantic version in `pubspec.yaml` for every published update.
For example, `1.1.0+3` produces GitHub tag `1.1.0`; the Windows executable
and manifest retain build number 3.

The build creates a fresh `build/releases/<version>-<timestamp>/` directory:

- `Release.zip`: full distribution, including the updater's executable, DLLs
  and Flutter data. Extract the entire archive.
- `update.zip`: only the overlay payload and its manifest.
- `SHA256SUMS.txt`: manual verification checksums.

Default invocation creates local artifacts. `-Publish` creates a GitHub Release
for the clean, pushed source commit and attaches both archives. Existing tags are
not overwritten. The project's existing ignored `lib/secrets.dart` remains a
local prerequisite for overlay builds; it must not be committed.

Existing users need the full distribution once to obtain the updater.
Afterwards they update from the tray. Release 1.0.1 contains only `Release.zip`;
the updater does not guess its format or treat it as an update package.

## Installation contract

`update.zip` has the Flutter Release files at archive root and
`overlay-update.json` with schema 1, application `twitch_chat_overlay`, version,
and the managed top-level roots. It excludes the updater directory.

Size and SHA-256 must match the GitHub release asset metadata. Missing checksums,
unexpected URLs, mismatching versions, unsafe paths, duplicate paths, symlinks,
junctions, missing runtime files and oversized archives are rejected. HTTPS and
the repository's release permissions form the trust boundary; the checksum
checks integrity and does not replace executable code signing.

Dart performs extraction and installation in worker isolates. Files are staged
in `.overlay-update/stage` on the installation volume. Any overlay file or folder
may be replaced: new or previously unknown names do not need an allowlist or a
manifest entry. Actual extracted roots are recorded in the installed manifest;
obsolete roots from the previous manifest are removed. Files outside these roots
remain untouched. The `updater` directory is always skipped, case-insensitively,
even if included in the archive. `.overlay-update` is reserved for the transaction.
SharedPreferences in AppData remain untouched.

A flushed journal records the rollback plan before any file move. Old roots
move into backup, new roots into place, and the journal is removed at commit.
Exceptions restore the old installation. After interruption, reopening the
updater recovers from the journal before checking for a release. Recovery failure
retains the backup.

The small native Windows bridge only reads EXE version metadata, manages the
installation mutex and communicates with the overlay process. It matches the
full executable path, sends `TwitchChatOverlay.PrepareForUpdate`, and Dart polls
for exit for up to 12 seconds. It never kills processes by name. An older or
unresponsive overlay must be closed manually through its tray.

The updater and overlay have separate Flutter engines and data directories.
The updater's running files are excluded from updates. Changing the updater
itself requires a full distribution; schema 1 application updates remain compatible.

## Develop and test

```powershell
cd updater
flutter pub get
flutter test
flutter analyze
flutter run -d windows -- --install-dir D:/path/to/overlay --locale en
```

The updater uses the overlay's Inter font assets via relative asset paths.
Tests use temporary installations and fake HTTP/native bridges; they do not stop
the user's running overlay. They cover successful installation, cancellation,
bad checksums, unsafe archives, rollback, journal recovery and controller states.

Widget tests exercise available/download/error/success screens and the minimum
window size. They also save real Flutter renders in `updater/build/previews/`.

References:
[GitHub Releases API](https://docs.github.com/en/rest/releases/releases),
[archive package](https://pub.dev/packages/archive).
