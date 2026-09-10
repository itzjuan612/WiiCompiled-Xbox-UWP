# Configure the UWP (x86_64-w64-mingw32uwp) build of WiiCompiled.
# Mirrors configure-native.ps1 but:
#   - uses the validated UWP toolchain file (UWPToolchain.cmake)
#   - targets the native-build-uwp dir (cache already seeded by seed-cache-uwp.ps1)
#   - builds Dawn from source (AURORA_DAWN_PROVIDER=vendor) since no UWP prebuilt exists
#   - SDL3 from source (AURORA_SDL3_PROVIDER=vendor)
# The seeded cache supplies the vendored dep source dirs + cppwinrt include dir;
# CMake 4.x drops -D path args, so we rely on the cache, not CLI path args.
[CmdletBinding()]
param(
    [string]$Workspace = 'C:\MKWii\wiicompiled',
    [string]$Toolchain = 'C:\MKWii\wiicompiled\Launcher\artifacts\portable-tools',
    [string]$BuildDir = 'C:\MKWii\wiicompiled\native-build-uwp'
)

$ErrorActionPreference = 'Stop'

function to-slash([string]$p) { return $p.Replace('\', '/') }

$cmakeBin = Join-Path $Toolchain 'CMake\bin\cmake.exe'
$ninja   = to-slash (Join-Path $Toolchain 'Ninja\ninja.exe')
$toolchainFile = to-slash (Join-Path $Workspace 'Launcher\cmake\UWPToolchain.cmake')
$build = to-slash $BuildDir
$runtime = to-slash (Join-Path $Workspace 'runtime')

$cmakeArgs = @(
    '-S', $runtime,
    '-B', $build,
    '-G', 'Ninja',
    "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile",
    "-DCMAKE_MAKE_PROGRAM=$ninja",
    '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_SYSTEM_PROCESSOR=x86_64',
    '-DAURORA_DAWN_PROVIDER=vendor',
    '-DAURORA_DAWN_LINKAGE=shared',
    '-DAURORA_SDL3_PROVIDER=vendor',
    '-DCMAKE_POLICY_DEFAULT_CMP0168=NEW',
    '-DMKW_TRANSLATED_COMPILE_JOBS=14',
    '-DFETCHCONTENT_FULLY_DISCONNECTED=OFF'
)

# Ensure ninja is discoverable for the generator + compile steps.
$oldPath = $env:PATH
$env:PATH = (Join-Path $Toolchain 'Ninja') + ';' + (Join-Path $Toolchain 'llvm-mingw\bin') + ';' + $oldPath

Write-Host "Configuring UWP build with pinned CMake + UWP toolchain..."
& $cmakeBin @cmakeArgs
$exit = $LASTEXITCODE
Write-Host "CMake configure exit code: $exit"

$env:PATH = $oldPath
exit $exit
