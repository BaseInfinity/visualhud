param(
    [switch] $Force
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleSource = Join-Path $ScriptRoot "wezterm\visualhud.lua"
$ConfigDir = Join-Path $HOME ".config\wezterm"
$ModuleTarget = Join-Path $ConfigDir "visualhud.lua"
$HomeConfig = Join-Path $HOME ".wezterm.lua"
$ConfigDirConfig = Join-Path $ConfigDir "wezterm.lua"

if (-not (Test-Path -LiteralPath $ModuleSource)) {
    throw "VisualHUD WezTerm module not found: $ModuleSource"
}

New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
Copy-Item -LiteralPath $ModuleSource -Destination $ModuleTarget -Force

$modulePath = $ModuleTarget.Replace("\", "/")
$generatedConfig = @"
local wezterm = require 'wezterm'
local config = wezterm.config_builder and wezterm.config_builder() or {}

local visualhud = dofile('$modulePath')
visualhud.apply_to_config(config)

return config
"@

function Test-VisualHudConfig($Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $content = Get-Content -LiteralPath $Path -Raw
    return $content -like "*visualhud.apply_to_config*" -or $content -like "*visualhud.lua*"
}

if (Test-VisualHudConfig $HomeConfig -or Test-VisualHudConfig $ConfigDirConfig) {
    Write-Output "VisualHUD WezTerm config already present."
    Write-Output "Module: $ModuleTarget"
    exit 0
}

if ((Test-Path -LiteralPath $HomeConfig) -or (Test-Path -LiteralPath $ConfigDirConfig)) {
    if (-not $Force) {
        $snippet = Join-Path $ConfigDir "visualhud-snippet.lua"
        Set-Content -LiteralPath $snippet -Value $generatedConfig -Encoding UTF8
        Write-Output "Installed module: $ModuleTarget"
        Write-Output "Existing WezTerm config found; not editing it automatically."
        Write-Output "Snippet written for manual merge: $snippet"
        Write-Output "Re-run with -Force to replace $HomeConfig with the VisualHUD config."
        exit 0
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    if (Test-Path -LiteralPath $HomeConfig) {
        Copy-Item -LiteralPath $HomeConfig -Destination "$HomeConfig.visualhud-backup-$timestamp" -Force
    }
    if (Test-Path -LiteralPath $ConfigDirConfig) {
        Copy-Item -LiteralPath $ConfigDirConfig -Destination "$ConfigDirConfig.visualhud-backup-$timestamp" -Force
    }
}

Set-Content -LiteralPath $HomeConfig -Value $generatedConfig -Encoding UTF8
Write-Output "Installed VisualHUD WezTerm module: $ModuleTarget"
Write-Output "Configured WezTerm: $HomeConfig"
