# Prepare the MSVC UWP build environment (idempotent).
#
# The MSVC toolchain lives under "E:\Program Files\Microsoft Visual Studio\...".
# Its include and lib\x64 dirs contain spaces, which CMake's Ninja FLAGS string
# cannot carry (Ninja word-splits on whitespace, shredding the path into bogus
# source-file tokens). UWPToolchainMSVC.cmake therefore references the MSVC
# include/lib via *space-free junctions*:
#     C:\msvcinc  ->  <MSVC>\include
#     C:\msvclib  ->  <MSVC>\lib\x64
# This script creates those junctions (idempotent: existing links are left alone).
# Run it before configure-uwp-msvc.ps1 / any MSVC UWP build.
$ErrorActionPreference = 'Stop'

$msvcRoot = 'E:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207'
$inc = "$msvcRoot\include"
$lib = "$msvcRoot\lib\x64"

if (-not (Test-Path $inc)) { throw "MSVC include dir missing: $inc" }
if (-not (Test-Path $lib)) { throw "MSVC lib dir missing: $lib" }

function ensure-junction([string]$link, [string]$target) {
    if (Test-Path $link) {
        $item = Get-Item $link
        if ($item.LinkType -eq 'Junction' -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-Host "Junction exists: $link -> $($item.Target)"
            return
        }
        throw "$link exists but is not a junction; remove it first"
    }
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Write-Host "Created junction: $link -> $target"
}

ensure-junction 'C:\msvcinc' $inc
ensure-junction 'C:\msvclib' $lib

# Sanity-check the key files the toolchain relies on through the junctions.
$checks = @(
    'C:\msvcinc\vcruntime.h',
    'C:\msvcinc\optional',
    'C:\msvcinc\excpt.h',
    'C:\msvcinc\vccorlib.h',
    'C:\msvclib\libvcruntime.lib',
    'C:\msvclib\libcmt.lib'
)
$fail = 0
foreach ($c in $checks) {
    if (Test-Path $c) { Write-Host "OK   $c" } else { Write-Host "MISS $c"; $fail = 1 }
}
if ($fail) { throw "MSVC junction verification failed" }
Write-Host "prepare-msvc-uwp: MSVC junctions ready"
