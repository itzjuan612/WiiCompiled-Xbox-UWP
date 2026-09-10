# Build the WiiCompiled target via ninja using the portable toolchain.
[CmdletBinding()]
param(
    [string]$Workspace = 'C:\MKWii\wiicompiled',
    [string]$Toolchain = 'C:\MKWii\wiicompiled\Launcher\artifacts\portable-tools',
    [string]$Target = 'WiiCompiled'
)

$ErrorActionPreference = 'Stop'
function to-slash([string]$p) { return $p.Replace('\', '/') }

$build = to-slash (Join-Path $Workspace 'native-build')
$ninja = to-slash (Join-Path $Toolchain 'Ninja\ninja.exe')

$oldPath = $env:PATH
$env:PATH = (Join-Path $Toolchain 'Ninja') + ';' + (Join-Path $Toolchain 'llvm-mingw\bin') + ';' + $oldPath

try {
    Write-Host "Building target: $Target"
    & $ninja -C $build $Target
    $exit = $LASTEXITCODE
    Write-Host "ninja exit code: $exit"
}
finally {
    $env:PATH = $oldPath
}
