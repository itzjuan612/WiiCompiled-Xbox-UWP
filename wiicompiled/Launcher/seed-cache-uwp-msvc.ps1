# Seed a fresh CMakeCache.txt for the UWP (MSVC) build. Mirrors seed-cache-uwp.ps1
# but points SDL at the SternXD/SDL3-uwp *fork* (not vanilla) and leaves Dawn to
# the runtime's UWP block (which sets FETCHCONTENT_SOURCE_DIR_DAWN + DAWN_ABSEIL_DIR
# to the vendored local trees and DAWN_FETCH_DEPENDENCIES OFF, so it builds
# offline from source). The vendored deps below (abseil/fmt/freetype/imgui/
# libusb/png/sqlite3/tracy/xxhash/zlib/zstd) are the same trees the native build
# uses; the UWP product is MSVC, so it does NOT use the native dawn_prebuilt.
$ErrorActionPreference = 'Stop'
$depsRoot = 'C:/MKWii/wiicompiled/Launcher/artifacts/dependencies'
$cppwinrt = "$depsRoot/cppwinrt"
$buildRoot = 'C:/MKWii/wiicompiled/native-build-uwp'

if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force }
New-Item -ItemType Directory -Path $buildRoot | Out-Null

$lines = @(
  '# CMake cache file (seeded for UWP/MSVC: SDL3-uwp fork + local Dawn, offline deps)',
  'CMAKE_HOME_DIRECTORY:INTERNAL=C:/MKWii/wiicompiled/runtime',
  # SDL3 -> the SternXD/SDL3-uwp fork (C++/CX WinRT driver), NOT vanilla SDL.
  "FETCHCONTENT_SOURCE_DIR_SDL:PATH=$depsRoot/SDL-uwp",
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
  # C++/WinRT (header-only) for the runtime's WinRT interop; also used by the
  # UWP app entry.
  "MKW_CPPWINRT_INCLUDE_DIR:PATH=$cppwinrt",
  # No FETCHCONTENT_SOURCE_DIR_DAWN here: the runtime's UWP block sets it to the
  # vendored local dawn tree + DAWN_ABSEIL_DIR + DAWN_FETCH_DEPENDENCIES OFF.
  'FETCHCONTENT_FULLY_DISCONNECTED:BOOL=OFF'
)

[IO.File]::WriteAllLines((Join-Path $buildRoot 'CMakeCache.txt'), $lines)
Write-Host "Wrote fresh UWP/MSVC cache with $($lines.Count) lines (SDL->fork, no dawn_prebuilt)"
