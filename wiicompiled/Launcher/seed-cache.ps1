# Create a fresh CMakeCache.txt containing every path CMake would otherwise need from
# the command line (FetchContent source dirs + cppwinrt include dir). CMake 4.x drops
# -D path arguments on the CLI, so seeding the cache is the reliable way to pin them.
$ErrorActionPreference = 'Stop'
$depsRoot = 'C:/MKWii/wiicompiled/Launcher/artifacts/dependencies'
$cppwinrt = "$depsRoot/cppwinrt"
$buildRoot = 'C:/MKWii/wiicompiled/native-build'

if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force }
New-Item -ItemType Directory -Path $buildRoot | Out-Null

$lines = @(
  '# CMake cache file (seeded for offline FetchContent + cppwinrt)',
  'CMAKE_HOME_DIRECTORY:INTERNAL=C:/MKWii/wiicompiled/runtime',
  "FETCHCONTENT_SOURCE_DIR_SDL:PATH=$depsRoot/SDL",
  "FETCHCONTENT_SOURCE_DIR_ABSEIL-CPP:PATH=$depsRoot/abseil-cpp",
  "FETCHCONTENT_SOURCE_DIR_DAWN_PREBUILT:PATH=$depsRoot/dawn_prebuilt",
  "FETCHCONTENT_SOURCE_DIR_FMT:PATH=$depsRoot/fmt",
  "FETCHCONTENT_SOURCE_DIR_FREETYPE:PATH=$depsRoot/freetype",
  "FETCHCONTENT_SOURCE_DIR_IMGUI:PATH=$depsRoot/imgui",
  "FETCHCONTENT_SOURCE_DIR_LIBUSB:PATH=$depsRoot/libusb",
  "FETCHCONTENT_SOURCE_DIR_PNG:PATH=$depsRoot/png",
  "FETCHCONTENT_SOURCE_DIR_SQLITE3:PATH=$depsRoot/sqlite3",
  "FETCHCONTENT_SOURCE_DIR_TRACY:PATH=$depsRoot/tracy",
  "FETCHCONTENT_SOURCE_DIR_XXHASH:PATH=$depsRoot/xxhash",
  "FETCHCONTENT_SOURCE_DIR_ZLIB:PATH=$depsRoot/zlib",
  "FETCHCONTENT_SOURCE_DIR_ZSTD:PATH=$depsRoot/zstd",
  "MKW_CPPWINRT_INCLUDE_DIR:PATH=$cppwinrt",
  'FETCHCONTENT_FULLY_DISCONNECTED:BOOL=ON'
)

[IO.File]::WriteAllLines((Join-Path $buildRoot 'CMakeCache.txt'), $lines)
Write-Host "Wrote fresh cache with $($lines.Count) lines (all paths seeded)"
