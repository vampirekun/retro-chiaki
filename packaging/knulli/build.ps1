[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceZip,

    [string]$Version = "v0.3.2",

    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$sourcePath = (Resolve-Path $SourceZip).Path

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot "dist"
}

$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$workRoot = Join-Path $tempRoot ("retro-chiaki-knulli-" + [guid]::NewGuid().ToString("N"))
$extractRoot = Join-Path $workRoot "source"
$stageRoot = Join-Path $workRoot "stage"
$stagePorts = Join-Path $stageRoot "roms\ports"
$sourceGameDir = Join-Path $extractRoot "ports\chiaki"
$stageGameDir = Join-Path $stagePorts "chiaki"
$launcher = Join-Path $PSScriptRoot "roms\ports\Chiaki.sh"
$gptk = Join-Path $PSScriptRoot "roms\ports\chiaki\chiaki.gptk"
$readme = Join-Path $PSScriptRoot "README.txt"
$zipName = "retro-chiaki-$Version-portmaster-knulli-h700.zip"
$outputZip = Join-Path $outputRoot $zipName

try {
    New-Item -ItemType Directory -Path $extractRoot, $stagePorts -Force | Out-Null
    Expand-Archive -LiteralPath $sourcePath -DestinationPath $extractRoot

    foreach ($requiredPath in @(
        (Join-Path $sourceGameDir "chiaki"),
        (Join-Path $sourceGameDir "chiaki-cli"),
        (Join-Path $sourceGameDir "chiaki.gptk"),
        (Join-Path $sourceGameDir "libs\libmaliegl.so"),
        $launcher,
        $gptk,
        $readme
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required package input is missing: $requiredPath"
        }
    }

    Copy-Item -LiteralPath $sourceGameDir -Destination $stageGameDir -Recurse
    Copy-Item -LiteralPath $launcher -Destination (Join-Path $stagePorts "Chiaki.sh")
    Copy-Item -LiteralPath $gptk -Destination (Join-Path $stageGameDir "chiaki.gptk")
    Copy-Item -LiteralPath $readme -Destination (Join-Path $stageGameDir "KNULLI-README.txt")

    # KNULLI's SDL contains the H700 controller handling, and its ALSA library
    # knows the Buildroot audio-plugin paths. Ubuntu's copies would shadow both
    # via LD_LIBRARY_PATH, breaking either controls or PipeWire-routed audio.
    foreach ($systemLibrary in @("libSDL2-2.0.so.0", "libasound.so.2")) {
        $bundledLibrary = Join-Path $stageGameDir ("libs\" + $systemLibrary)
        if (Test-Path -LiteralPath $bundledLibrary) {
            Remove-Item -LiteralPath $bundledLibrary -Force
        }
    }

    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
    if (Test-Path -LiteralPath $outputZip) {
        Remove-Item -LiteralPath $outputZip -Force
    }
    Compress-Archive -Path (Join-Path $stageRoot "*") -DestinationPath $outputZip -CompressionLevel Optimal

    $hash = Get-FileHash -LiteralPath $outputZip -Algorithm SHA256
    Write-Output $outputZip
    Write-Output ("SHA256: " + $hash.Hash.ToLowerInvariant())
}
finally {
    $resolvedWorkRoot = [System.IO.Path]::GetFullPath($workRoot)
    if ($resolvedWorkRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        $resolvedWorkRoot -ne $tempRoot -and
        (Test-Path -LiteralPath $resolvedWorkRoot)) {
        Remove-Item -LiteralPath $resolvedWorkRoot -Recurse -Force
    }
}
