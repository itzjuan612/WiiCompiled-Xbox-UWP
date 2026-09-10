[CmdletBinding()]
param(
    [string]$Workspace = 'C:\MKWii\wiicompiled',
    [string]$Toolchain = 'C:\MKWii\wiicompiled\Launcher\artifacts\portable-tools'
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

# Reconfigure against the seeded cache. Only the core toolchain flags are re-asserted;
# the FetchContent source dirs come from the seeded cache.
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
    '-DMKW_TRANSLATED_COMPILE_JOBS=14'
)

$oldPath = $env:PATH
$env:PATH = (Join-Path $Toolchain 'Ninja') + ';' + (Join-Path $Toolchain 'llvm-mingw\bin') + ';' + $oldPath

Write-Host "Reconfiguring native build with seeded cache..."
& $cmakeBin @cmakeArgs
$exit = $LASTEXITCODE
Write-Host "CMake configure exit code: $exit"

$env:PATH = $oldPath
