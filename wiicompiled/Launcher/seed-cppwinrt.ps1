# Append MKW_CPPWINRT_INCLUDE_DIR into the existing CMakeCache.txt so the
# cppwinrt headers are found (the -D argument is dropped by CMake 4.x).
$ErrorActionPreference = 'Stop'
$cache = 'C:\MKWii\wiicompiled\native-build\CMakeCache.txt'
$cppwinrt = 'C:/MKWii/wiicompiled/Launcher/artifacts/dependencies/cppwinrt'

$lines = [IO.File]::ReadAllLines($cache)
# Remove any existing MKW_CPPWINRT_INCLUDE_DIR line first
$filtered = $lines | Where-Object { $_ -notmatch '^MKW_CPPWINRT_INCLUDE_DIR' }
$filtered += "MKW_CPPWINRT_INCLUDE_DIR:PATH=$cppwinrt"
[IO.File]::WriteAllLines($cache, $filtered)
Write-Host "Seeded MKW_CPPWINRT_INCLUDE_DIR into cache"
