# =============================================================================
# UWP cross-compile toolchain for the MKW UWP port — MSVC (Option B).
#
# Replaces the Clang/llvm-mingw UWPToolchain.cmake for the Store target. The
# native Windows build stays on the pinned portable Clang toolchain; this file
# drives the UWP target with MSVC so the SternXD/SDL3-uwp C++/CX WinRT driver
# (and the UWP app activation entry) can be compiled — C++/CX is MSVC-only.
#
# WHY THIS FILE SETS SDK PATHS ITSELF
# -----------------------------------
# The Windows SDK 10.0.28000.0 at C:\WindowsSDK is a *partial, non-standard*
# install:
#   * Its per-version registry key (...\v10.0\10.0.28000.0) is ABSENT, so neither
#     vcvarsall.bat nor CMake's FindWindowsSDK auto-discovers it. `vcvarsall x64`
#     therefore only puts the MSVC dirs + the *ucrt* SDK dir on INCLUDE/LIB —
#     NOT um/winrt/shared, and NOT the um\x64 import libs.
#   * Include\10.0.28000.0\um has the full header set but NO x64 sub-folder
#     (no *.winmd); the WinRT union metadata (Windows.winmd) is at
#     C:\WindowsSDK\UnionMetadata\10.0.28000.0, and platform.winmd has been
#     COPIED there too (from the VS vcpackages dir) so BOTH WinMDs sit in a single
#     directory whose path has NO spaces (C:\WindowsSDK\UnionMetadata\10.0.28000.0).
#
# CMake's Ninja build runs cl/link WITHOUT the toolchain's ENV{} values (those
# only reach CMake's own compiler probe), so the SDK dirs are baked into the
# compile/link *flags*. Flags are word-split on spaces (NOT semicolons), so each
# /LIBPATH:/AI is a separate whitespace-delimited token. The C++/CX WinMD search
# is a *compile-time* need (/AI on the cl line), hence CMAKE_*_FLAGS, not the
# linker flags.
#
# WHAT IS DELIBERATELY NOT SET GLOBALLY
# -------------------------------------
#   * No global /ZW (C++/CX) and no global /std: C++/CX requires C++14 and is only
#     needed by the SDL3-uwp WinRT driver (the fork adds /ZW to its own targets)
#     and the UWP app activation entry (added per-target). Aurora, Dawn, the
#     runtime and abseil stay plain C++17/20 (C++/WinRT header-only). Forcing /ZW
#     globally would collide with the runtime's cxx_std_17/20 targets.
#   * CMAKE_SYSTEM_NAME is WindowsStore (not Windows) so CMake sets
#     WINDOWS_STORE=1. That variable is load-bearing: Dawn's CMake auto-disables
#     Vulkan/GL/glslang for UWP (D3D12-only) and the SDL-uwp fork branches on it
#     to enable the WinRT video/audio/power/filesystem drivers.

cmake_minimum_required(VERSION 3.25)

# --- Portable roots ---------------------------------------------------------
# Every hardcoded path below can be overridden by the environment, so the same
# toolchain file drives a WiiCompiled-Installer-managed build on any machine:
#   MKW_MSVC_ROOT   <VC>\Tools\MSVC\<ver> of an installed VS2022 C++ toolset
#   MKW_SDK_ROOT    Windows SDK install root (contains Include\, Lib\, bin\)
#   MKW_SDK_VER     SDK version folder name, e.g. 10.0.28000.0
#   MKW_MSCVINC / MKW_MSCVLIB   space-free junctions onto the MSVC include/lib
#                               dirs (Ninja word-splits flags, so no spaces)
#   MKW_PYTHON      interpreter with jinja2 + markupsafe for Dawn/SDL codegen
# The launcher-relative paths (ASM clang, UWP stub headers) are derived from
# this file's own location, so no variable is needed once the portable-tools
# bootstrap has run (Launcher/artifacts/portable-tools) and the stub headers sit
# in the tracked Launcher/uwp-msvc-stubs.
get_filename_component(MSVCUWP_LAUNCHER_DIR "${CMAKE_CURRENT_LIST_DIR}" DIRECTORY)

if(DEFINED ENV{MKW_MSVC_ROOT})
  set(MSVCUWP_MSVC_ROOT "$ENV{MKW_MSVC_ROOT}")
else()
  set(MSVCUWP_MSVC_ROOT "E:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.44.35207")
endif()
if(DEFINED ENV{MKW_SDK_ROOT})
  set(MSVCUWP_SDK_ROOT "$ENV{MKW_SDK_ROOT}")
else()
  set(MSVCUWP_SDK_ROOT "C:/WindowsSDK")
endif()
if(DEFINED ENV{MKW_SDK_VER})
  set(MSVCUWP_SDK_VER "$ENV{MKW_SDK_VER}")
else()
  set(MSVCUWP_SDK_VER "10.0.28000.0")
endif()

set(CMAKE_SYSTEM_NAME WindowsStore)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_SYSTEM_VERSION "${MSVCUWP_SDK_VER}")

# WHY THE ASM LANGUAGE USES Clang (see CMAKE_ASM_COMPILER below):
# The product embeds its guest DOL/REL data sections in a generated AT&T-syntax
# file (generated/data_sections_init_blobs.S: ".section .rdata,\"dr\"", ".globl",
# ".incbin"). ml64 (the MSVC assembler) cannot assemble AT&T. And when the ASM
# compiler is MSVC, abseil's CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL is
# applied to ASM targets and has no MASM mapping, failing generation with
# "MSVC_RUNTIME_LIBRARY value 'MultiThreadedDLL' not known for this ASM
# compiler". Using the UWP LLVM/Clang wrapper for ASM fixes both: Clang assembles
# AT&T, and a Clang ASM compiler ignores the MSVC runtime-library value (the
# native Clang build behaves identically). The blob is pure C-linked .rdata
# (extern "C" kData__*), so its COFF objects link cleanly into the MSVC exe.

# --- Toolchain roots --------------------------------------------------------
set(MSVCUWP_MSVC_BIN  "${MSVCUWP_MSVC_ROOT}/bin/Hostx64/x64")
set(MSVCUWP_MSVC_INC  "${MSVCUWP_MSVC_ROOT}/include")
set(MSVCUWP_MSVC_LIB  "${MSVCUWP_MSVC_ROOT}/lib/x64")
set(MSVCUWP_SDK_INC   "${MSVCUWP_SDK_ROOT}/Include/${MSVCUWP_SDK_VER}")
set(MSVCUWP_SDK_LIB   "${MSVCUWP_SDK_ROOT}/Lib/${MSVCUWP_SDK_VER}")
set(MSVCUWP_SDK_BIN   "${MSVCUWP_SDK_ROOT}/bin/${MSVCUWP_SDK_VER}/x64")
# Single no-space dir holding BOTH WinMDs (Windows.winmd + platform.winmd).
set(MSVCUWP_UNIMETA   "${MSVCUWP_SDK_ROOT}/UnionMetadata/${MSVCUWP_SDK_VER}")

# --- Compilers (MSVC) -------------------------------------------------------
set(CMAKE_C_COMPILER   "${MSVCUWP_MSVC_BIN}/cl.exe")
set(CMAKE_CXX_COMPILER "${MSVCUWP_MSVC_BIN}/cl.exe")
set(CMAKE_RC_COMPILER  "${MSVCUWP_SDK_BIN}/rc.exe")
set(CMAKE_LINKER       "${MSVCUWP_MSVC_BIN}/link.exe")
set(CMAKE_AR           "${MSVCUWP_MSVC_BIN}/lib.exe")
set(CMAKE_DLLTOOL      "")  # MSVC uses dumpbin/lib, not the LLVM tools.

# ASM: UWP LLVM/Clang wrapper (handles the generated AT&T data blob + any
# vendored .asm). Targets x86_64-w64-mingw32uwp (COFF); ml64 cannot assemble
# AT&T and would fail on the MSVC runtime-library value. The C/CXX targets keep
# MSVC (see above); the CMake ASM language is separate.
# The wrapper ships with the launcher-prepared portable llvm-mingw, so it is
# derived from this file's location; MKW_ASM_BIN overrides for exotic layouts.
if(DEFINED ENV{MKW_ASM_BIN})
  set(MSVCUWP_ASM_BIN "$ENV{MKW_ASM_BIN}")
else()
  set(MSVCUWP_ASM_BIN "${MSVCUWP_LAUNCHER_DIR}/artifacts/portable-tools/llvm-mingw/bin")
endif()
set(MSVCUWP_ASM_CLANG "${MSVCUWP_ASM_BIN}/x86_64-w64-mingw32uwp-clang.exe")
set(MSVCUWP_ASM_AR    "${MSVCUWP_ASM_BIN}/x86_64-w64-mingw32uwp-llvm-ar.exe")
set(CMAKE_ASM_COMPILER        "${MSVCUWP_ASM_CLANG}")
set(CMAKE_ASM_COMPILER_AR     "${MSVCUWP_ASM_AR}")
set(CMAKE_ASM_COMPILER_RANLIB "${MSVCUWP_ASM_AR}")

# --- Include dirs + C++/CX WinMD search, baked into every C/CXX compile ----
# Only *space-free* dirs may live in CMAKE_*_FLAGS: CMake passes them to Ninja,
# which word-splits the FLAGS string on whitespace, so a space-containing path
# (the MSVC <vcroot>\include under "E:\Program Files\...") would be shredded into
# bogus source-file tokens. The MSVC internal include (vcruntime.h, excpt.h,
# vccorlib.h) is therefore supplied via the INCLUDE *environment* — see the
# configure-uwp-msvc.ps1 driver, which sets INCLUDE/LIB/LIBPATH/PATH exactly as
# vcvarsall does (Ninja + cl inherit the process env, which is not word-split).
# The space-free SDK dirs below are added as a plain /I (internal pool; NOT
# CMAKE_*_STANDARD_INCLUDE_DIRECTORIES, which CMake emits as -external:I and
# MSVC does not search for its internal headers). The MSVC <vcroot>\include and
# lib\x64 dirs are reached via space-free *junctions* (C:\msvcinc, C:\msvclib)
# because the real paths contain spaces (Ninja word-splits FLAGS). The junctions
# are created by Launcher/prepare-msvc-uwp.ps1 (idempotent). MSVC include goes
# FIRST (it supplies vcruntime.h, excpt.h, the STL, vccorlib.h), then the SDK
# ucrt/um/winrt/shared. ucrt first among the SDK dirs, then um, winrt (C++/CX
# projection), shared. /AI uses the SPACE form (/AI <dir>, not /AI:) — the dir
# is space-free, so it stays one token. /AI is a compile-time C++/CX metadata
# search; harmless for non-C++/CX targets.
set(MSVCUWP_MSCVINC "$ENV{MKW_MSCVINC}")
if(NOT MSVCUWP_MSCVINC)
  set(MSVCUWP_MSCVINC "C:/msvcinc")
endif()
set(MSVCUWP_MSCVLIB "$ENV{MKW_MSCVLIB}")
if(NOT MSVCUWP_MSCVLIB)
  set(MSVCUWP_MSCVLIB "C:/msvclib")
endif()
# UWP-only header stubs (first, so a stub is found before any real header).
# Currently dbghelp.h: abseil's crash-symbolizer includes it, but dbghelp.h is
# desktop-only (absent from the UWP SDK). The stub degrades symbolization to
# "no symbol" (the runtime doesn't use it meaningfully on UWP/Xbox).
# These headers are tracked in the repo (Launcher/uwp-msvc-stubs), so the path
# derives from this file's location; MKW_UWP_STUBS overrides for exotic layouts.
if(DEFINED ENV{MKW_UWP_STUBS})
  set(MSVCUWP_UWP_STUBS "$ENV{MKW_UWP_STUBS}")
else()
  set(MSVCUWP_UWP_STUBS "${MSVCUWP_LAUNCHER_DIR}/uwp-msvc-stubs")
endif()
# WINAPI_FAMILY=WINAPI_FAMILY_APP for EVERY target: the whole UWP/Xbox binary
# must compile in the Windows Store API partition. CMake does NOT inject this
# automatically for Ninja (only the SDL fork adds it to its own targets), and
# the SDK's winapifamily.h otherwise defaults WINAPI_FAMILY to DESKTOP_APP —
# which would compile desktop code and fail the Store link. Applied globally so
# Dawn/abseil/Aurora/the runtime all see the App partition (the SDL fork's own
# identical define is a benign no-op redefinition).
# _WIN32_WINNT must be 0x0A00 (Windows 10 / Xbox) for the WINAPI_FAMILY
# partition macros (winapifamily.h) to gate correctly: on the Store partition
# this turns WINAPI_PARTITION_DESKTOP off. Without it the SDK defaults
# _WIN32_WINNT to 0x0501 and the partition checks use the pre-Store semantics
# (all partitions "active"), which makes deps like abseil's symbolize.cc take
# the Win32 symbolizer (whose Sym API is Store-gated/absent) and fail. The
# native Clang UWP wrapper sets the same thing, so this matches it.
# _AMD64_ is the x64 arch macro that Windows.h normally defines (its arch-mapping
# block at lines 106-137) BEFORE it includes winnt.h. But winnt.h(159) gates on
# defined(_AMD64_)/_X86_/_ARM64_, and some TUs reach winnt.h via <windef.h>/<
# winerror.h> BEFORE <Windows.h> (Dawn's D3DError.cpp includes windef.h+winerror.h
# from D3DError.h, then Windows.h) — at which point _AMD64_ is still undefined and
# winnt.h fails with "#error No Target Architecture". This target is always x64
# (CMAKE_SYSTEM_PROCESSOR=x86_64), so pre-defining _AMD64_ is correct and matches
# exactly what Windows.h would set; Windows.h's own block is guarded with
# !defined(_AMD64_), so there is no double-definition. (The native Clang/mingw
# path is unaffected — its mingw winnt.h self-defines the arch macro.)
set(MSVCUWP_UWP_DEFINE "/DWINAPI_FAMILY=WINAPI_FAMILY_APP /D_WIN32_WINNT=0x0A00 /DWINVER=0x0A00 /D_AMD64_")
# The runtime + vendored Aurora were written for Clang, which on x86-64
# pre-defines __x86_64__ and provides the __builtin_* intrinsic family. MSVC
# defines neither (it uses _M_X64 and has no __builtin_*). This shim is
# FORCE-INCLUDED (/FI) into every MSVC C/CXX TU so the shared sources see the
# identical environment on both toolchains (arch macro + __builtin_* shims).
# It is a no-op for the native Clang build (wired here only) and is itself a
# no-op for every vendor header where MSVC already defines the symbol.
set(MSVCUWP_BUILTIN_COMPAT "${MSVCUWP_UWP_STUBS}/msvc_builtin_compat.h")
set(MSVCUWP_INCLUDE_FLAGS
    "${MSVCUWP_UWP_DEFINE} /FI ${MSVCUWP_BUILTIN_COMPAT} /I${MSVCUWP_UWP_STUBS} /I${MSVCUWP_MSCVINC} /I${MSVCUWP_SDK_INC}/ucrt /I${MSVCUWP_SDK_INC}/um /I${MSVCUWP_SDK_INC}/winrt /I${MSVCUWP_SDK_INC}/shared /AI ${MSVCUWP_UNIMETA}")
set(CMAKE_C_FLAGS   "${MSVCUWP_INCLUDE_FLAGS}" CACHE INTERNAL "" FORCE)
set(CMAKE_CXX_FLAGS "${MSVCUWP_INCLUDE_FLAGS}" CACHE INTERNAL "" FORCE)

# --- RC compiler include search --------------------------------------------
# rc.exe does not reliably inherit the INCLUDE env the way cl does, so the
# resource files (e.g. zlib1.rc -> <winver.h>) fail with RC1015. Bake the same
# space-free include set (MSVC junction + SDK um/winrt/shared) into the RC
# flags. (/AI and the UWP defines are irrelevant to the resource compiler.)
set(MSVCUWP_RC_FLAGS
    "/I${MSVCUWP_MSCVINC} /I${MSVCUWP_SDK_INC}/ucrt /I${MSVCUWP_SDK_INC}/um /I${MSVCUWP_SDK_INC}/winrt /I${MSVCUWP_SDK_INC}/shared")
set(CMAKE_RC_FLAGS "${MSVCUWP_RC_FLAGS}" CACHE INTERNAL "" FORCE)

# --- MSVC + SDK import-lib search, baked into every link -------------------
# /LIBPATH gives the linker the MSVC CRT/STL libs (libvcruntime, msvcp140,
# libcmt) via the space-free C:\msvclib junction, plus the ucrt + um\x64 UWP
# import libs (windowsapp, d3d12, dxgi, ...). Whitespace-separated so each is
# its own token. (No /AI here — it belongs on the compile line; see above.)
set(MSVCUWP_LIBPATH_FLAGS
    "/LIBPATH:${MSVCUWP_MSCVLIB} /LIBPATH:${MSVCUWP_SDK_LIB}/ucrt/x64 /LIBPATH:${MSVCUWP_SDK_LIB}/um/x64")
set(CMAKE_EXE_LINKER_FLAGS    "${MSVCUWP_LIBPATH_FLAGS}" CACHE INTERNAL "" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS "${MSVCUWP_LIBPATH_FLAGS}" CACHE INTERNAL "" FORCE)
set(CMAKE_MODULE_LINKER_FLAGS "${MSVCUWP_LIBPATH_FLAGS}" CACHE INTERNAL "" FORCE)
# NB: CMAKE_CXX_STANDARD_LIBRARIES is intentionally NOT overridden; for
# Windows/MSVC the default system libs are handled by CMake's platform layer +
# the MSVC linker's default library list, and the /LIBPATH above already makes
# the ucrt + um\x64 SDK import libs discoverable.

# Expose the C++/CX WinMD search root + a ready /AI compile flag for targets
# that need C++/CX explicitly (the SDL-uwp fork and the UWP app entry). The
# toolchain already adds /AI to every compile via CMAKE_CXX_FLAGS; these are
# convenience exports in case a target wants to add it itself.
set(MSVCUWP_WINMD_DIRS "${MSVCUWP_UNIMETA}" CACHE INTERNAL "C++/CX WinMD search roots")
set(MSVCUWP_AI_COMPILE_FLAG "/AI ${MSVCUWP_UNIMETA}" CACHE INTERNAL "C++/CX /AI compile flag")

# --- Environment for CMake's own compiler probe (try_compile) ---------------
# The build steps rely on the flags above; these env vars make CMake's initial
# "compiler works" probe see a complete Store environment for the partial SDK.
set(ENV{INCLUDE} "${MSVCUWP_MSVC_INC};${MSVCUWP_SDK_INC}/ucrt;${MSVCUWP_SDK_INC}/um;${MSVCUWP_SDK_INC}/winrt;${MSVCUWP_SDK_INC}/shared")
set(ENV{LIB}     "${MSVCUWP_MSVC_LIB};${MSVCUWP_SDK_LIB}/ucrt/x64;${MSVCUWP_SDK_LIB}/um/x64")
set(ENV{LIBPATH} "${MSVCUWP_UNIMETA}")
set(ENV{WindowsSDKDir}     "${MSVCUWP_SDK_ROOT}/")
set(ENV{WindowsSdkVersion} "${MSVCUWP_SDK_VER}")
set(ENV{PATH} "${MSVCUWP_MSVC_BIN};${MSVCUWP_SDK_BIN};$ENV{PATH}")

# Pin the Python used by generator scripts (Dawn codegen, SDL, etc.) to a known
# interpreter with jinja2 + markupsafe. MKW_PYTHON wins; otherwise fall back to
# whatever python is on PATH (the WiiCompiled-Installer verifies it can import
# jinja2 + markupsafe before configuring, and reports what to install if not).
if(DEFINED ENV{MKW_PYTHON} AND NOT "$ENV{MKW_PYTHON}" STREQUAL "")
  set(Python3_EXECUTABLE "$ENV{MKW_PYTHON}")
else()
  if(EXISTS "E:/anaconda3/envs/openwebui/python.exe")
    set(Python3_EXECUTABLE "E:/anaconda3/envs/openwebui/python.exe")
  else()
    find_program(MSVCUWP_PYTHON NAMES python python3)
    if(MSVCUWP_PYTHON)
      set(Python3_EXECUTABLE "${MSVCUWP_PYTHON}")
    else()
      set(Python3_EXECUTABLE "python")
    endif()
  endif()
endif()

# MSVC runtime: keep the *dynamic* CRT (default) so the product links
# VCRUNTIME140.dll / vccorlib140.dll, which are present in the Xbox/UWP runtime.
# (A static CRT would bloat the binary and is unnecessary for a UWP app.)
# Verified on this machine (crt_probe / crt_probe23 probes): the /MD objects'
# /DEFAULTLIB directives resolve through msvcprt.lib (MSVCP140.dll import),
# vcruntime.lib (VCRUNTIME140.dll import) and ucrt.lib (api-ms-win-crt-* api-set
# imports); the C++/CX dynamic ABI resolves through vccorlib.lib (vccorlib140.dll
# import). All present under C:\msvclib (MSVC lib\x64 junction) + SDK ucrt\x64.
