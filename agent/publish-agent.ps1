<#
.SYNOPSIS
    Builds the downloadable SimHub Agent (a single SimHubAgent.exe + SimHubAgent.json).

.DESCRIPTION
    1. Writes a production appsettings.json (project appsettings.json with Agent.ServerBaseUrl replaced)
       to a temp folder and embeds it into the exe (-p:AgentSettingsFile=...). No settings file ships next to the exe.
    2. dotnet publish SimCenter.Agent.Tray as a self-contained single-file win-x64 exe.
    3. Copies the exe to <OutDir>\SimHubAgent.exe and writes <OutDir>\SimHubAgent.json
       ({version, builtAt, sizeBytes, sha256}) for the web Telemetry App page.
    4. Removes the old zip bundle (<OutDir>\SimHubAgent.zip) if it is still there.

    The agent keeps its data (device key, outbox.db) under %LOCALAPPDATA%\SimCenter\Agent.
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
$DownloadExeName = 'SimHubAgent.exe'
$SettingsFileName = 'appsettings.json'
$LegacyZipFileName = 'SimHubAgent.zip'
$MetadataFileName = 'SimHubAgent.json'
$RuntimeIdentifier = 'win-x64'
$Configuration = 'Release'
$JsonDepth = 10

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
New-Item -ItemType Directory -Force -Path $publishDir | Out-Null

try {
    # Production settings to embed: project defaults with only Agent.ServerBaseUrl replaced.
    $sourceSettingsPath = Join-Path (Split-Path -Parent $projectPath) $SettingsFileName
    $settings = [IO.File]::ReadAllText($sourceSettingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $settings.Agent.ServerBaseUrl = $ServerBaseUrl.TrimEnd('/')
    $embeddedSettingsPath = Join-Path $workRoot $SettingsFileName
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($embeddedSettingsPath, ($settings | ConvertTo-Json -Depth $JsonDepth), $utf8NoBom)

    Write-Host "Publishing SimHub Agent $Version ($RuntimeIdentifier, single-file, settings embedded) ..."
    & dotnet publish $projectPath `
        -c $Configuration `
        -r $RuntimeIdentifier `
        --self-contained true `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true `
        -p:DebugType=None `
        "-p:InformationalVersion=$Version" `
        -p:IncludeSourceRevisionInInformationalVersion=false `
        "-p:AgentSettingsFile=$embeddedSettingsPath" `
        -o $publishDir
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }

    $publishedExe = Join-Path $publishDir $PublishedExeName
    if (-not (Test-Path -LiteralPath $publishedExe)) {
        throw "Published exe not found: $publishedExe"
    }

    # Copy to a temp name in OutDir first, then rename, so the served file is never half-written.
    $exePath = Join-Path $OutDir $DownloadExeName
    $tempExe = "$exePath.tmp"
    Copy-Item -LiteralPath $publishedExe -Destination $tempExe -Force
    Move-Item -LiteralPath $tempExe -Destination $exePath -Force

    $exeInfo = Get-Item -LiteralPath $exePath
    $metadata = [ordered]@{
        version   = $Version
        builtAt   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        sizeBytes = $exeInfo.Length
        sha256    = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $metadataPath = Join-Path $OutDir $MetadataFileName
    [IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json), $utf8NoBom)

    $legacyZip = Join-Path $OutDir $LegacyZipFileName
    if (Test-Path -LiteralPath $legacyZip) {
        Remove-Item -LiteralPath $legacyZip -Force
        Write-Host "Removed old bundle $legacyZip"
    }

    Write-Host "Created $exePath ($($exeInfo.Length) bytes)"
    Write-Host "Created $metadataPath"
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
