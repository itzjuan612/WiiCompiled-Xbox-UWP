# UWP cross-compile toolchain for the portable llvm-mingw toolchain.
#
# Targets x86_64-w64-mingw32uwp using the UWP Clang wrappers shipped in the
# portable toolchain. The wrappers already inject:
#   --target x86_64-w64-mingw32uwp
#   -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00
#   -DWINAPI_FAMILY=WINAPI_FAMILY_APP   (Windows Store API only)
#   -DUNICODE -D_UCRT
# and append linker flags: -lwindowsapp -lucrtapp
#
# CMAKE_SYSTEM_NAME is WindowsStore (not Windows) so that CMake sets
# WINDOWS_STORE=1. That variable is load-bearing: Dawn's CMake branches on it
# (Win32 + NOT WINDOWS_STORE enables Vulkan, which does not exist on UWP/Xbox)
# and SDL3/other deps use it to select Store APIs.
#
# Header resolution: the mingw toolchain ships its own Windows header tree
# (d3d12.h, dxgi*.h, wrl.h, dxcapi.h, ucrt headers). We rely on those (proven
# by the UWP smoke test) and do NOT add SDK include dirs: mixing SDK ucrt/
# corecrt.h into the mingw CRT header chain triggers a vcruntime.h not-found
# error.
#
# Link resolution: the mingw toolchain's own target lib dir
# (llvm-mingw/x86_64-w64-mingw32/lib) already contains the UWP import libs
# (libwindowsapp.a, libucrtapp.a, libd3d12.a, libdxgi.a, libd3d11.a, ...), so
# linking is self-contained. Note: CMake's compiler detection overwrites
# CMAKE_*_IMPLICIT_LINK_DIRECTORIES in a toolchain file with the compiler's
# real search dirs (which are exactly the mingw target dirs), so do not rely
# on setting them here.

cmake_minimum_required(VERSION 3.25)

set(CMAKE_SYSTEM_NAME WindowsStore)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Point CMake at the UWP wrapper compilers.
set(CMAKE_C_COMPILER  "C:/MKWii/wiicompiled/Launcher/artifacts/portable-tools/llvm-mingw/bin/x86_64-w64-mingw32uwp-clang.exe")
set(CMAKE_CXX_COMPILER "C:/MKWii/wiicompiled/Launcher/artifacts/portable-tools/llvm-mingw/bin/x86_64-w64-mingw32uwp-clang++.exe")
set(CMAKE_RC_COMPILER "C:/MKWii/wiicompiled/Launcher/artifacts/portable-tools/llvm-mingw/bin/x86_64-w64-mingw32uwp-windres.exe")

# Pin the Python used by generator scripts (Dawn codegen, SDL, etc.) to a known
# interpreter that has jinja2 + markupsafe (system jinja2 path in Dawn's
# generator). `python` resolves to an Anaconda env on this machine.
set(Python3_EXECUTABLE "E:/anaconda3/envs/openwebui/python.exe")
set(Python3_NumPy_INCLUDE_DIR "E:/anaconda3/envs/openwebui/include")

set(CMAKE_C_FLAGS   "")
set(CMAKE_CXX_FLAGS "")
set(CMAKE_EXE_LINKER_FLAGS "")
