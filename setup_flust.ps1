$ErrorActionPreference = "Stop"

function Normalize-PathValue([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $value = [Environment]::ExpandEnvironmentVariables($Value.Trim().Trim('"'))
    return [System.IO.Path]::GetFullPath($value).TrimEnd('\')
}

function Get-JsonSettings([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return [PSCustomObject]@{} }
        $parsed = $raw | ConvertFrom-Json
        if ($null -eq $parsed) { return [PSCustomObject]@{} }
        return $parsed
    }
    catch {
        throw "Cannot parse VS Code settings JSON at '$Path'. Fix its JSON syntax first. Details: $($_.Exception.Message)"
    }
}

function Get-DartExeFromSdkRoot([string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Root)) { return $null }
    try { $rootPath = Normalize-PathValue $Root } catch { return $null }
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { return $null }

    # Flutter bundles Dart inside bin\cache\dart-sdk. A standalone Dart SDK
    # normally has bin\dart.exe directly under its SDK root.
    $candidates = @(
        (Join-Path $rootPath 'bin\cache\dart-sdk\bin\dart.exe'),
        (Join-Path $rootPath 'bin\dart.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }
    return $null
}

function Get-RootsFromCommandPath([string]$CommandPath) {
    $roots = @()
    if ([string]::IsNullOrWhiteSpace($CommandPath)) { return $roots }
    try {
        $full = Normalize-PathValue $CommandPath
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $dir = Split-Path -Parent $full
        } elseif (Test-Path -LiteralPath $full -PathType Container) {
            $dir = $full
        } else {
            return $roots
        }
        # Walk upward because `where.exe dart` can return either Flutter's
        # bin wrapper or the bundled Dart SDK's bin\dart.exe.
        for ($i = 0; $i -lt 6 -and $dir; $i++) {
            $roots += $dir
            $parent = Split-Path -Parent $dir
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
            $dir = $parent
        }
    } catch { }
    return $roots
}

function Get-WhereResults([string]$Name) {
    try {
        $result = @(& where.exe $Name 2>$null)
        return @($result | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } catch {
        return @()
    }
}

Write-Host ""
Write-Host "Flust Setup" -ForegroundColor Cyan
Write-Host "=============================="

$appData = $env:APPDATA
if ([string]::IsNullOrWhiteSpace($appData)) {
    $appData = [Environment]::GetFolderPath('ApplicationData')
}
if ([string]::IsNullOrWhiteSpace($appData)) {
    Write-Host "ERROR: Cannot determine the Windows AppData directory." -ForegroundColor Red
    exit 1
}

# Update whichever VS Code user settings already exist. If neither exists,
# create the regular VS Code settings file.
$settingsPaths = @(
    (Join-Path $appData 'Code\User\settings.json'),
    (Join-Path $appData 'Code - Insiders\User\settings.json')
)
$existingSettingsPaths = @($settingsPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($existingSettingsPaths.Count -eq 0) {
    $existingSettingsPaths = @($settingsPaths[0])
}

# Read SDK hints from existing VS Code settings.
$settingsObjects = @{}
foreach ($settingsPath in $existingSettingsPaths) {
    $settingsObjects[$settingsPath] = Get-JsonSettings $settingsPath
}

$flutterHints = @()
if (-not [string]::IsNullOrWhiteSpace($env:FLUTTER_ROOT)) {
    $flutterHints += [PSCustomObject]@{ Source = 'FLUTTER_ROOT'; Path = $env:FLUTTER_ROOT }
}
foreach ($settingsPath in $existingSettingsPaths) {
    $settingsObject = $settingsObjects[$settingsPath]
    if ($null -ne $settingsObject -and $settingsObject.PSObject.Properties['dart.flutterSdkPath']) {
        $value = [string]$settingsObject.'dart.flutterSdkPath'
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $flutterHints += [PSCustomObject]@{ Source = 'dart.flutterSdkPath'; Path = $value }
        }
    }
}

$dartExecutable = $null
$detectedFrom = $null

# 1. FLUTTER_ROOT, then 2. dart.flutterSdkPath.
foreach ($hint in $flutterHints) {
    $dartExecutable = Get-DartExeFromSdkRoot $hint.Path
    if ($dartExecutable) {
        $detectedFrom = $hint.Source
        break
    }
}

# 3. Find Flutter on PATH and infer its SDK root from ...\bin\flutter(.bat).
if (-not $dartExecutable) {
    foreach ($flutterCommand in (Get-WhereResults 'flutter')) {
        foreach ($root in (Get-RootsFromCommandPath $flutterCommand)) {
            $dartExecutable = Get-DartExeFromSdkRoot $root
            if ($dartExecutable) {
                $detectedFrom = 'where.exe flutter'
                break
            }
        }
        if ($dartExecutable) { break }
    }
}

# 4. Find Dart on PATH and walk upward to either a Flutter or Dart SDK root.
if (-not $dartExecutable) {
    foreach ($dartCommand in (Get-WhereResults 'dart')) {
        foreach ($root in (Get-RootsFromCommandPath $dartCommand)) {
            $dartExecutable = Get-DartExeFromSdkRoot $root
            if ($dartExecutable) {
                $detectedFrom = 'where.exe dart'
                break
            }
        }
        if ($dartExecutable) { break }
    }
}

if (-not $dartExecutable) {
    Write-Host "ERROR: Flutter/Dart SDK was not found." -ForegroundColor Red
    Write-Host "Checked: FLUTTER_ROOT, dart.flutterSdkPath, where.exe flutter and where.exe dart."
    Write-Host "Install Flutter or add its bin directory to PATH, then run this script again."
    exit 1
}

Write-Host "Dart SDK found:" -ForegroundColor Green
Write-Host "  $dartExecutable"
Write-Host "Detected via: $detectedFrom"

# Add/update Flust setting while retaining all other settings.
foreach ($settingsPath in $existingSettingsPaths) {
    $settingsDir = Split-Path -Parent $settingsPath
    if (-not (Test-Path -LiteralPath $settingsDir -PathType Container)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $settings = $settingsObjects[$settingsPath]
    if ($null -eq $settings) { $settings = [PSCustomObject]@{} }

    $settings | Add-Member -MemberType NoteProperty -Name 'flust.dartPath' -Value $dartExecutable -Force
    $json = $settings | ConvertTo-Json -Depth 100
    Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8

    Write-Host "Updated: $settingsPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Flust configured successfully!" -ForegroundColor Green
Write-Host "Restart or reload VS Code to apply the setting."
