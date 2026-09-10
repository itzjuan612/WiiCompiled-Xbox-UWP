# Build pres_test.exe (Xbox presentation probe) with the native Win32 target.
# NOT the UWP wrapper - this probes the plain Win32 PE + d3d12/dxgi import path
# that Option C (Xbox GDK native) depends on.
[CmdletBinding()]
param(
    [string]$Toolchain = 'C:\MKWii\wiicompiled\Launcher\artifacts\portable-tools'
)
$ErrorActionPreference = 'Stop'
$cxx = Join-Path $Toolchain 'llvm-mingw\bin\x86_64-w64-mingw32-clang++.exe'
$out = 'C:\MKWii\wiicompiled\Launcher\uwp-dawn\pres_test\pres_test.exe'
$src = 'C:\MKWii\wiicompiled\Launcher\uwp-dawn\pres_test\pres_test.cpp'

& $cxx -O2 -static -static-libgcc -static-libstdc++ -o $out $src -ld3d12 -ldxgi -luser32 -lgdi32 -lkernel32
$exit = $LASTEXITCODE
Write-Host "Build exit: $exit"
if ($exit -eq 0) {
    Write-Host ("Size: " + (Get-Item $out).Length + " bytes")
    # Show the actual dynamic imports (Q1 probe target)
    Write-Host "Dynamic imports:"
    & (Join-Path $Toolchain 'llvm-mingw\bin\llvm-objdump.exe') -p $out | Select-String 'DLL Name'
}
exit $exit
