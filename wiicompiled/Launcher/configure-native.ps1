[CmdletBinding()]
param(
    [string]$Workspace = 'C:\MKWii\wiicompiled',
    [string]$Toolchain = 'C:\MKWii\wiicompiled\Launcher\artifacts\portable-tools',
    [string]$Dependencies = 'C:\MKWii\wiicompiled\Launcher\artifacts\dependencies',
    [string]$BuildDir = 'C:\MKWii\wiicompiled\native-build'
)

$ErrorActionPreference = 'Stop'

function to-slash([string]$p) { return $p.Replace('\', '/') }

$cmakeBin = Join-Path $Toolchain 'CMake\bin\cmake.exe'
$cc      = to-slash (Join-Path $Toolchain 'llvm-mingw\bin\x86_64-w64-mingw32-clang.exe')
$cxx     = to-slash (Join-Path $Toolchain 'llvm-mingw\bin\x86_64-w64-mingw32-clang++.exe')
$rc      = to-slash (Join-Path $Toolchain 'llvm-mingw\bin\x86_64-w64-mingw32-windres.exe')
$ninja   = to-slash (Join-Path $Toolchain 'Ninja\ninja.exe')
$build   = to-slash (Join-Path $Workspace 'native-build')
$runtime = to-slash (Join-Path $Workspace 'runtime')
$cwinrt  = to-slash (Join-Path $Dependencies 'cppwinrt')

$cmakeArgs = @(
    '-S', $runtime,
    '-B', $build,
    '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$ninja",
    "-DCMAKE_C_COMPILER=$cc",
    "-DCMAKE_CXX_COMPILER=$cxx",
    "-DCMAKE_RC_COMPILER=$rc",
    '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_SYSTEM_PROCESSOR=x86_64',
    '-DAURORA_DAWN_PROVIDER=package',
    '-DAURORA_SDL3_PROVIDER=vendor',
    '-DCMAKE_POLICY_DEFAULT_CMP0168=NEW',
    '-DFETCHCONTENT_FULLY_DISCONNECTED=ON',
    '-DAWK:FILEPATH=',
    "-DMKW_CPPWINRT_INCLUDE_DIR=$cwinrt",
    '-DMKW_TRANSLATED_COMPILE_JOBS=14',
    "-DFETCHCONTENT_SOURCE_DIR_SDL=" + (to-slash (Join-Path $Dependencies 'SDL')),
    "-DFETCHCONTENT_SOURCE_DIR_ABSEIL-CPP=" + (to-slash (Join-Path $Dependencies 'abseil-cpp')),
    "-DFETCHCONTENT_SOURCE_DIR_DAWN_PREBUILT=" + (to-slash (Join-Path $Dependencies 'dawn_prebuilt')),
    "-DFETCHCONTENT_SOURCE_DIR_FMT=" + (to-slash (Join-Path $Dependencies 'fmt')),
    "-DFETCHCONTENT_SOURCE_DIR_FREETYPE=" + (to-slash (Join-Path $Dependencies 'freetype')),
    "-DFETCHCONTENT_SOURCE_DIR_IMGUI=" + (to-slash (Join-Path $Dependencies 'imgui')),
    "-DFETCHCONTENT_SOURCE_DIR_LIBUSB=" + (to-slash (Join-Path $Dependencies 'libusb')),
    "-DFETCHCONTENT_SOURCE_DIR_PNG=" + (to-slash (Join-Path $Dependencies 'png')),
    "-DFETCHCONTENT_SOURCE_DIR_SQLITE3=" + (to-slash (Join-Path $Dependencies 'sqlite3')),
    "-DFETCHCONTENT_SOURCE_DIR_TRACY=" + (to-slash (Join-Path $Dependencies 'tracy')),
    "-DFETCHCONTENT_SOURCE_DIR_XXHASH=" + (to-slash (Join-Path $Dependencies 'xxhash')),
    "-DFETCHCONTENT_SOURCE_DIR_ZLIB=" + (to-slash (Join-Path $Dependencies 'zlib')),
    "-DFETCHCONTENT_SOURCE_DIR_ZSTD=" + (to-slash (Join-Path $Dependencies 'zstd'))
)

# Ensure ninja is discoverable for the generator check
$oldPath = $env:PATH
$env:PATH = (Join-Path $Toolchain 'Ninja') + ';' + (Join-Path $Toolchain 'llvm-mingw\bin') + ';' + $oldPath

Write-Host "Configuring native build with pinned CMake 4.3.3..."
& $cmakeBin @cmakeArgs
$exit = $LASTEXITCODE
Write-Host "CMake configure exit code: $exit"

$env:PATH = $oldPath
