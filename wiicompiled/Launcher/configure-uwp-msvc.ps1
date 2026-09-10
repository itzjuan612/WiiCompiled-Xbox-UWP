# Configure (and optionally build) the UWP (MSVC) build of WiiCompiled.
#
# This is the MSVC/Option-B counterpart of configure-uwp.ps1 (the Clang/llvm-mingw
# UWP path). It mirrors configure-uwp.ps1 but:
#   - uses the MSVC UWP toolchain file (UWPToolchainMSVC.cmake)
#   - targets the native-build-uwp dir (cache seeded by seed-cache-uwp-msvc.ps1,
#     which points SDL at the SternXD/SDL3-uwp fork and Dawn at the local tree)
#   - builds Dawn from source (AURORA_DAWN_PROVIDER=vendor)
#   - SDL3 from the fork source (AURORA_SDL3_PROVIDER=vendor)
#
# WHY THIS SCRIPT SETS THE ENVIRONMENT
# ------------------------------------
# The Windows SDK 10.0.28000.0 at C:\WindowsSDK is a partial install whose
# per-version registry key is absent, so vcvarsall.bat does not auto-discover it
# (it only adds the MSVC dirs + the ucrt SDK dir). And the MSVC <vcroot>\include
# path contains spaces ("E:\Program Files\...") which CMake's Ninja FLAGS string
# cannot carry (Ninja word-splits it). The standard vcvars-style fix is to put
# the space-containing dirs in INCLUDE/LIB/LIBPATH *environment* variables —
# CMake's try_compile probe and every Ninja/cl/link step inherit the process
# environment, which is NOT word-split. The toolchain file additionally bakes in
# the space-free SDK include/lib dirs as flags as a belt-and-suspenders backup.

[CmdletBinding()]
param(
    [string]$Workspace = 'C:\MKWii\wiicompiled',
    [string]$Toolchain = 'C:\MKWii\wiicompiled\Launcher\artifacts\portable-tools',
    [string]$BuildDir  = 'C:\MKWii\wiicompiled\native-build-uwp'
)

# NB: no $ErrorActionPreference='Stop' — CMake emits benign CMake Warning (dev)
# lines to stderr (e.g. the MSVC ASM-compiler determination), which PowerShell
# promotes to NativeCommandError; with Stop that would abort the configure.
# Errors are surfaced via $LASTEXITCODE instead.

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
$unimeta  = "$sdkRoot\UnionMetadata\$sdkVer"   # Windows.winmd + platform.winmd

# --- Complete UWP environment (vcvars-equivalent for the partial SDK) --------
$env:INCLUDE = ($msvcInc, "$sdkInc\ucrt", "$sdkInc\um", "$sdkInc\winrt", "$sdkInc\shared") -join ';'
$env:LIB     = ($msvcLib, "$sdkLib\ucrt\x64", "$sdkLib\um\x64") -join ';'
$env:LIBPATH = "$unimeta;$msvcLib;$sdkLib\ucrt\x64;$sdkLib\um\x64"
$env:WindowsSDKDir     = "$sdkRoot\"
$env:WindowsSdkVersion = $sdkVer
$env:PATH  = "$msvcBin;$sdkBin;$env:PATH"

$cmakeBin   = Join-Path $Toolchain 'CMake\bin\cmake.exe'
$ninja      = to-slash (Join-Path $Toolchain 'Ninja\ninja.exe')
$toolchainFile = to-slash (Join-Path $Workspace 'Launcher\cmake\UWPToolchainMSVC.cmake')
$build      = to-slash $BuildDir
$runtime    = to-slash (Join-Path $Workspace 'runtime')

$cmakeArgs = @(
    '-S', $runtime,
    '-B', $build,
    '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$ninja",
    "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile",
    '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_SYSTEM_PROCESSOR=x86_64',
    '-DAURORA_DAWN_PROVIDER=vendor',
    '-DAURORA_DAWN_LINKAGE=shared',
    '-DAURORA_SDL3_PROVIDER=vendor',
    '-DCMAKE_POLICY_DEFAULT_CMP0168=NEW',
    '-DMKW_TRANSLATED_COMPILE_JOBS=14',
    '-DFETCHCONTENT_FULLY_DISCONNECTED=OFF'
)

Write-Host "Configuring UWP (MSVC) build with pinned CMake + MSVC UWP toolchain..."
& $cmakeBin @cmakeArgs
$exit = $LASTEXITCODE
Write-Host "CMake configure exit code: $exit"
exit $exit
