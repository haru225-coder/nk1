param(
    [string]$GodotPath = '',
    [string]$PythonPath = 'python',
    [switch]$SkipExport
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$DefaultGodot = Join-Path $RepoRoot '.godot-tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
$SelfTestScene = 'res://tools/SelfTestHost.tscn'
$ExportRelativePath = 'build\windows\NanhaiLizhiZhuan.exe'
$ExportPath = Join-Path $RepoRoot $ExportRelativePath
$PushedLocation = $false

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    if (Test-Path -LiteralPath $DefaultGodot) {
        $GodotPath = $DefaultGodot
    } else {
        $GodotCommand = Get-Command godot -ErrorAction SilentlyContinue
        if ($null -eq $GodotCommand) {
            throw 'Godot 4.6.3 was not found. Pass -GodotPath explicitly.'
        }
        $GodotPath = $GodotCommand.Source
    }
}

function Invoke-NativeStep {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments
    )

    Write-Host ('==> {0}' -f $Name) -ForegroundColor Cyan
    & $FilePath @Arguments
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        throw ('[{0}] failed with exit code {1}.' -f $Name, $ExitCode)
    }
}

function Test-ExportStartup {
    param([string]$ExecutablePath)

    if (-not (Test-Path -LiteralPath $ExecutablePath)) {
        throw ('[Export startup] executable not found: {0}' -f $ExecutablePath)
    }

    Write-Host '==> Exported executable startup' -ForegroundColor Cyan
    $Process = Start-Process -FilePath $ExecutablePath `
        -WorkingDirectory (Split-Path -Parent $ExecutablePath) `
        -WindowStyle Hidden `
        -PassThru
    try {
        Start-Sleep -Seconds 5
        if ($Process.HasExited) {
            throw ('[Export startup] executable exited early with code {0}.' -f $Process.ExitCode)
        }
    } finally {
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force
            $Process.WaitForExit()
        }
    }
}

try {
    Push-Location $RepoRoot
    $PushedLocation = $true

    Invoke-NativeStep 'Project validation' $PythonPath @('validate_project.py')
    Invoke-NativeStep 'Story logic audit' $PythonPath @('tools\audit_story_logic.py')
    Invoke-NativeStep 'Asset reference audit' $PythonPath @('tools\audit_asset_refs.py')
    Invoke-NativeStep 'Godot editor scan' $GodotPath @('--headless', '--editor', '--path', $RepoRoot, '--quit')
    Invoke-NativeStep 'Core TestRunner' $GodotPath @('--headless', '--path', $RepoRoot, '-s', 'scripts/systems/TestRunner.gd')

    foreach ($SelfTest in @(
        'res://tools/SaveManagerSelfTest.gd',
        'res://tools/StoryEventChainSelfTest.gd',
        'res://tools/IntentResolverSelfTest.gd',
        'res://tools/TaikouSmokeSelfTest.gd'
    )) {
        $Name = [System.IO.Path]::GetFileNameWithoutExtension($SelfTest)
        Invoke-NativeStep $Name $GodotPath @(
            '--headless',
            '--path', $RepoRoot,
            '--scene', $SelfTestScene,
            '--', $SelfTest
        )
    }

    if (-not $SkipExport) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ExportPath) | Out-Null
        Invoke-NativeStep 'Windows release export' $GodotPath @(
            '--headless',
            '--path', $RepoRoot,
            '--export-release', 'Windows Desktop', $ExportPath
        )
        Test-ExportStartup $ExportPath
    }

    Write-Host 'Release verification PASS.' -ForegroundColor Green
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    if ($PushedLocation) {
        Pop-Location
    }
}
