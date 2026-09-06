[CmdletBinding()]
param(
    [switch]$Publish,
    [string]$NotesFile
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $projectRoot

function Invoke-Checked {
    param([scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
}

$versionMatch = [regex]::Match([IO.File]::ReadAllText((Join-Path $projectRoot 'pubspec.yaml')), '(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$')
if (-not $versionMatch.Success) { throw 'Expected a stable version with a build number in pubspec.yaml.' }
$releaseVersion = $versionMatch.Groups[1].Value
$releaseTag = $releaseVersion.Split('+')[0]
if ($Publish) {
    $changes = git status --porcelain
    if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Commit all source changes before publishing.' }
    $releaseCommit = git rev-parse HEAD
    $releaseBranch = git branch --show-current
    $remoteHead = git ls-remote origin "refs/heads/$releaseBranch"
    if ($LASTEXITCODE -ne 0 -or -not $remoteHead -or $remoteHead.Split()[0] -ne $releaseCommit) {
        throw 'Push the current commit to origin before publishing.'
    }
}

Invoke-Checked { flutter test }
Invoke-Checked { flutter analyze }
Push-Location (Join-Path $projectRoot 'updater')
try {
    Invoke-Checked { flutter test }
    Invoke-Checked { flutter analyze }
    Invoke-Checked { flutter build windows --release }
} finally { Pop-Location }
Invoke-Checked { flutter build windows --release }

# Every run gets a new directory: no stale files from older packages.
$output = Join-Path $projectRoot ("build/releases/" + $releaseVersion + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$payload = Join-Path $output 'payload'
$bundle = Join-Path $output 'bundle'
$updaterOutput = Join-Path $projectRoot 'updater/build/windows/x64/runner/Release'
[IO.Directory]::CreateDirectory($payload) | Out-Null
[IO.Directory]::CreateDirectory($bundle) | Out-Null

$flutterOutput = Join-Path $projectRoot 'build/windows/x64/runner/Release'
$exe = Join-Path $flutterOutput 'twitch_chat_overlay.exe'
if ([Diagnostics.FileVersionInfo]::GetVersionInfo($exe).ProductVersion -ne $releaseVersion) {
    throw 'The built executable does not match pubspec.yaml.'
}

$managedRoots = @(Get-ChildItem -LiteralPath $flutterOutput | Where-Object {
    $_.Name -notin @('updater', '.overlay-update', 'overlay-update.json') -and $_.Extension -ne '.pdb'
} | ForEach-Object Name)
foreach ($name in $managedRoots) {
    $source = Join-Path $flutterOutput $name
    if (-not (Test-Path -LiteralPath $source)) { throw "Required release file missing: $name" }
    Copy-Item -LiteralPath $source -Destination $payload -Recurse
}
$manifest = @{
    schema = 1
    application = 'twitch_chat_overlay'
    version = $releaseVersion
    roots = @($managedRoots) + @('overlay-update.json')
} | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText((Join-Path $payload 'overlay-update.json'), $manifest, [Text.UTF8Encoding]::new($false))

Get-ChildItem -LiteralPath $payload | Copy-Item -Destination $bundle -Recurse
$bundledUpdater = Join-Path $bundle 'updater'
[IO.Directory]::CreateDirectory($bundledUpdater) | Out-Null
Get-ChildItem -LiteralPath $updaterOutput | Where-Object { $_.Extension -ne '.pdb' } | Copy-Item -Destination $bundledUpdater -Recurse

Add-Type -AssemblyName System.IO.Compression.FileSystem
$updateZip = Join-Path $output 'update.zip'
$releaseZip = Join-Path $output 'Release.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($payload, $updateZip, 'Optimal', $false)
[IO.Compression.ZipFile]::CreateFromDirectory($bundle, $releaseZip, 'Optimal', $false)
foreach ($zipPath in @($updateZip, $releaseZip)) {
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        if (-not $zip.GetEntry('twitch_chat_overlay.exe') -or -not $zip.GetEntry('overlay-update.json')) {
            throw "Invalid archive root: $zipPath"
        }
        if ($zipPath -eq $releaseZip -and -not $zip.GetEntry('updater/overlay_updater.exe')) {
            throw 'The full package is missing the updater.'
        }
    } finally { $zip.Dispose() }
}
$checksums = @($updateZip, $releaseZip) | ForEach-Object {
    (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($_)
}
[IO.File]::WriteAllLines((Join-Path $output 'SHA256SUMS.txt'), $checksums, [Text.UTF8Encoding]::new($false))
Write-Output "Release artifacts: $output"
Write-Output 'Release.zip is the full distribution. update.zip is installed by the updater.'

if ($Publish) {
    $releaseArgs = @('release', 'create', $releaseTag, $releaseZip, $updateZip, (Join-Path $output 'SHA256SUMS.txt'),
        '--repo', 'dealnotedev/twitch_chat_overlay', '--target', $releaseCommit, '--title', "Twitch Chat Overlay $releaseTag")
    if ($NotesFile) { $releaseArgs += @('--notes-file', $NotesFile) }
    else { $releaseArgs += '--generate-notes' }
    Invoke-Checked { gh @releaseArgs }
}
