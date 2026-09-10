# Build the UWP (MSVC) WiiCompiled product. Sets the same UWP environment as
# configure-uwp-msvc.ps1 (the partial SDK needs INCLUDE/LIB/LIBPATH/PATH), then
# runs Ninja. Optional -Target to build a specific target (default: WiiCompiled).
[CmdletBinding()]
param(
    [string]$Workspace = 'C:\MKWii\wiicompiled',
    [string]$Toolchain = 'C:\MKWii\wiicompiled\Launcher\artifacts\portable-tools',
    [string]$BuildDir  = 'C:\MKWii\wiicompiled\native-build-uwp',
    [string]$Target    = 'WiiCompiled'
)
# NB: no $ErrorActionPreference='Stop' (CMake/MSVC write benign warnings to
# stderr that PowerShell would promote to terminating NativeCommandError).

function to-slash([string]$p) { return $p.Replace('\', '/') }

# --- MSVC + SDK roots (from UWPToolchainMSVC.cmake) -------------------------
$vs2022   = 'E:\Program Files\Microsoft Visual Studio\2022\Community'
$msvcRoot = "$vs2022\VC\Tools\MSVC\14.44.35207"
$msvcBin  = "$msvcRoot\bin\Hostx64\x64"
$msvcInc  = "$msvcRoot\include"
$msvcLib  = "$msvcRoot\lib\x64"
$sdkRoot  = 'C:\WindowsSDK'
$sdkVer   = '10.0.28000.0'
$sdkInc   = "$sdkRoot\Include\$sdkVer"
$sdkLib   = "$sdkRoot\Lib\$sdkVer"
$sdkBin   = "$sdkRoot\bin\$sdkVer\x64"
$unimeta  = "$sdkRoot\UnionMetadata\$sdkVer"

$env:INCLUDE = @($msvcInc, "$sdkInc\ucrt", "$sdkInc\um", "$sdkInc\winrt", "$sdkInc\shared") -join ';'
$env:LIB     = @($msvcLib, "$sdkLib\ucrt\x64", "$sdkLib\um\x64") -join ';'
$env:LIBPATH = "$unimeta;$msvcLib;$sdkLib\ucrt\x64;$sdkLib\um\x64"
$env:WindowsSDKDir     = "$sdkRoot\"
$env:WindowsSdkVersion = $sdkVer
$env:PATH  = "$msvcBin;$sdkBin;$env:PATH"

$cmake = Join-Path $Toolchain 'CMake\bin\cmake.exe'
$build = to-slash $BuildDir

Write-Host "Building $Target (UWP/MSVC)..."
& $cmake --build $build --config Release --target $Target
$exit = $LASTEXITCODE
Write-Host "Build exit code: $exit"
exit $exit
