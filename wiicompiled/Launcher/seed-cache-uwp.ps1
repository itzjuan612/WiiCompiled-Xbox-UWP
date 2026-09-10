# Seed a fresh CMakeCache.txt for the UWP build. Mirrors seed-cache.ps1 but:
#   - targets the uwp build dir
#   - EXCLUDES FETCHCONTENT_SOURCE_DIR_DAWN_PREBUILT (the Win32 prebuilt is unusable
#     for UWP; Dawn is built from source via the vendor provider instead)
#   - sets FETCHCONTENT_FULLY_DISCONNECTED=OFF so Dawn + its deps can be fetched
#     from GitHub at configure time.
$ErrorActionPreference = 'Stop'
$depsRoot = 'C:/MKWii/wiicompiled/Launcher/artifacts/dependencies'
$cppwinrt = "$depsRoot/cppwinrt"
$buildRoot = 'C:/MKWii/wiicompiled/native-build-uwp'

if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force }
New-Item -ItemType Directory -Path $buildRoot | Out-Null

$lines = @(
  '# CMake cache file (seeded for UWP: offline vendored deps, source-built Dawn)',
  'CMAKE_HOME_DIRECTORY:INTERNAL=C:/MKWii/wiicompiled/runtime',
  "FETCHCONTENT_SOURCE_DIR_SDL:PATH=$depsRoot/SDL",
  "FETCHCONTENT_SOURCE_DIR_ABSEIL-CPP:PATH=$depsRoot/abseil-cpp",
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
  'FETCHCONTENT_FULLY_DISCONNECTED:BOOL=OFF'
)

[IO.File]::WriteAllLines((Join-Path $buildRoot 'CMakeCache.txt'), $lines)
Write-Host "Wrote fresh UWP cache with $($lines.Count) lines (no dawn_prebuilt, disconnected=OFF)"
