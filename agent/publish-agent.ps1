<#
.SYNOPSIS
    Builds the downloadable SimHub Agent bundle (SimHubAgent.zip + SimHubAgent.json).

.DESCRIPTION
    1. dotnet publish SimCenter.Agent.Tray as a self-contained single-file win-x64 exe.
    2. Renames the exe to "SimHub Agent.exe" (single-file bundles do not depend on the file name).
    3. Writes appsettings.json next to the exe (project appsettings.json with Agent.ServerBaseUrl replaced).
    4. Adds a short Korean usage guide (UTF-8 with BOM).
    5. Zips everything to <OutDir>\SimHubAgent.zip and writes <OutDir>\SimHubAgent.json
       ({version, builtAt, sizeBytes, sha256}) for the web Telemetry App page.

    The backend serves <OutDir> at /downloads when Downloads:Directory points to it.
    Never commit the output: the repository is public.
    Compatible with Windows PowerShell 5.1. Keep this file ASCII-only.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File agent\publish-agent.ps1 -OutDir D:\Toy\SimCenterServer\downloads
#>
[CmdletBinding()]
param(
    [string] $ServerBaseUrl = 'https://desktop-jc07560.tail4a150e.ts.net:8443',

    [Parameter(Mandatory = $true)]
    [string] $OutDir,

    [string] $Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRelativePath = 'src\SimCenter.Agent.Tray\SimCenter.Agent.Tray.csproj'
$PublishedExeName = 'SimCenter.Agent.Tray.exe'
$BundleExeName = 'SimHub Agent.exe'
$SettingsFileName = 'appsettings.json'
$ZipFileName = 'SimHubAgent.zip'
$MetadataFileName = 'SimHubAgent.json'
$RuntimeIdentifier = 'win-x64'
$Configuration = 'Release'
$JsonDepth = 10

# Korean file name ("usage".txt) built from code points so this script stays ASCII-only.
$UsageFileName = [string]::new([char[]]@(0xC0AC, 0xC6A9, 0xBC95)) + '.txt'

# Korean usage guide (UTF-8, CRLF) as base64 so this script stays ASCII-only.
$UsageTextBase64 =
    'U2ltSHViIEFnZW50IOyCrOyaqeuylQ0KDQoxLiDslZXstpUg7YyM7J28IOyViOydmCDrqqjrk6Ag' +
    '7YyM7J287J2EIO2VnCDtj7TrjZTsl5Ag7ZKA7Ja0IOyjvOyEuOyalC4NCiAgIOyVley2lSDtjIzs' +
    'nbwg7JWI7JeQ7IScIOuwlOuhnCDsi6TtlontlZjrqbQg7ISk7KCVIO2MjOydvChhcHBzZXR0aW5n' +
    'cy5qc29uKeydhCDssL7sp4Ag66q77ZWp64uI64ukLg0KDQoyLiAiU2ltSHViIEFnZW50LmV4ZSLr' +
    'pbwg7Iuk7ZaJ7ZWp64uI64ukLg0KICAg7ISc66qF65CY7KeAIOyViuydgCDtlITroZzqt7jrnqjs' +
    'nbTrnbwgV2luZG93cyBTbWFydFNjcmVlbiDqsr3qs6DqsIAg65ywIOyImCDsnojslrTsmpQuDQog' +
    'ICDsnbTrlYzripQgIuy2lOqwgCDsoJXrs7Qi66W8IOuIhOuluCDrkqQgIuyLpO2WiSLsnYQg64iE' +
    '66W066m0IOuQqeuLiOuLpC4NCg0KMy4gRjEgMjXsnZggU2V0dGluZ3MgPiBUZWxlbWV0cnkgU2V0' +
    'dGluZ3Psl5DshJwg7JWE656Y7LKY65+8IOunnuy2peuLiOuLpC4NCiAgIC0gVURQIFRlbGVtZXRy' +
    'eTogT24NCiAgIC0gVURQIEZvcm1hdDogMjAyNQ0KICAgLSBVRFAgUG9ydDogMjA3NzcNCiAgIC0g' +
    'VURQIElQIEFkZHJlc3M6IEFnZW5066W8IOyLpO2Wie2VmOuKlCBQQ+ydmCBJUCAo6rCZ7J2AIFBD' +
    '652866m0IDEyNy4wLjAuMSkNCg0KNC4g7Ju57J2YIFRlbGVtZXRyeSBBcHAg7ZmU66m07JeQ7ISc' +
    'ICLsl7DqsrAg7L2U65OcIOuwnOq4iSLsnYQg64iE66W06rOgLA0KICAg67Cb7J2AIOy9lOuTnOul' +
    'vCBBZ2VudCDssL3snZgg7Jew6rKwIOy9lOuTnCDsubjsl5Ag64Sj7J2AIOuSpCAi7Jew6rKwIuyd' +
    'hCDriITrpoXri4jri6QuDQoNCuywuOqzoA0KLSDssL3snYQg64ur7JWE64+EIO2KuOugiOydtOyX' +
    'kOyEnCDqs4Tsho0g7Iuk7ZaJ65Cp64uI64ukLiDsooXro4zripQg7Yq466CI7J20IOyVhOydtOy9' +
    'mCDrqZTribTsl5DshJwg7ZWp64uI64ukLg0KLSDshJzrsoTsl5Ag67O064K06riwIOyghCDquLDr' +
    'oZ3snYAg7J20IO2PtOuNlOydmCBvdXRib3guZGLsl5Ag7J6g7IucIOuztOq0gO2VqeuLiOuLpC4N' +
    'CiAg7Y+0642U66W8IOyYruq4sOqxsOuCmCDsp4Dsmrgg65WM64qUIEFnZW5066W8IOuovOyggCDs' +
    'ooXro4ztlbQg7KO87IS47JqULg0K'

function Get-DefaultVersion {
    $date = (Get-Date).ToUniversalTime().ToString('yyyyMMdd')
    $sha = $null
    try {
        $output = & git -C $PSScriptRoot rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0) {
            $sha = "$output".Trim()
        }
    }
    catch {
        $sha = $null
    }
    if ([string]::IsNullOrWhiteSpace($sha)) {
        return "dev-$date"
    }
    return "$sha-$date"
}

if ([string]::IsNullOrWhiteSpace($ServerBaseUrl)) {
    throw 'ServerBaseUrl must not be empty.'
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-DefaultVersion
}

$projectPath = Join-Path $PSScriptRoot $ProjectRelativePath
if (-not (Test-Path -LiteralPath $projectPath)) {
    throw "Project not found: $projectPath"
}

$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$workRoot = Join-Path ([IO.Path]::GetTempPath()) ("simhub-agent-publish-" + [Guid]::NewGuid().ToString('N'))
$publishDir = Join-Path $workRoot 'publish'
$bundleDir = Join-Path $workRoot 'bundle'
New-Item -ItemType Directory -Force -Path $publishDir, $bundleDir | Out-Null

try {
    Write-Host "Publishing SimHub Agent $Version ($RuntimeIdentifier, single-file) ..."
    & dotnet publish $projectPath `
        -c $Configuration `
        -r $RuntimeIdentifier `
        --self-contained true `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:DebugType=None `
        "-p:InformationalVersion=$Version" `
        -p:IncludeSourceRevisionInInformationalVersion=false `
        -o $publishDir
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }

    $publishedExe = Join-Path $publishDir $PublishedExeName
    if (-not (Test-Path -LiteralPath $publishedExe)) {
        throw "Published exe not found: $publishedExe"
    }

    # Copy everything except debug symbols, renaming the exe.
    Get-ChildItem -LiteralPath $publishDir -File |
        Where-Object { $_.Extension -ne '.pdb' -and $_.Name -ne $SettingsFileName } |
        ForEach-Object {
            $targetName = if ($_.Name -eq $PublishedExeName) { $BundleExeName } else { $_.Name }
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $bundleDir $targetName)
        }

    # appsettings.json: project defaults with only Agent.ServerBaseUrl replaced.
    $sourceSettingsPath = Join-Path (Split-Path -Parent $projectPath) $SettingsFileName
    $settings = [IO.File]::ReadAllText($sourceSettingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $settings.Agent.ServerBaseUrl = $ServerBaseUrl.TrimEnd('/')
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $bundleDir $SettingsFileName), ($settings | ConvertTo-Json -Depth $JsonDepth), $utf8NoBom)

    # Usage guide: UTF-8 with BOM so Notepad on any locale shows Korean correctly.
    $usageText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($UsageTextBase64))
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText((Join-Path $bundleDir $UsageFileName), $usageText, $utf8Bom)

    # Zip to a temp file first, then move, so the served file is never half-written.
    $tempZip = Join-Path $workRoot $ZipFileName
    Compress-Archive -Path (Join-Path $bundleDir '*') -DestinationPath $tempZip -CompressionLevel Optimal

    $zipPath = Join-Path $OutDir $ZipFileName
    Move-Item -LiteralPath $tempZip -Destination $zipPath -Force

    $zipInfo = Get-Item -LiteralPath $zipPath
    $metadata = [ordered]@{
        version   = $Version
        builtAt   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        sizeBytes = $zipInfo.Length
        sha256    = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $metadataPath = Join-Path $OutDir $MetadataFileName
    [IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json), $utf8NoBom)

    Write-Host "Created $zipPath ($($zipInfo.Length) bytes)"
    Write-Host "Created $metadataPath"
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
