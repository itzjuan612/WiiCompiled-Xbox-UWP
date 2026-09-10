# Standalone Dawn UWP build harness (validation of the highest-risk unknown:
# does Dawn's D3D12 backend compile+link for x86_64-w64-mingw32uwp?).
#
# Configure with the UWP toolchain file, then `ninja webgpu_dawn`.
cmake_minimum_required(VERSION 3.22)
project(dawn_uwp_harness C CXX)

set(DAWN_ROOT "C:/MKWii/wiicompiled/Launcher/artifacts/dependencies/dawn")
set(DAWN_ABSEIL_DIR "C:/MKWii/wiicompiled/Launcher/artifacts/dependencies/abseil-cpp" CACHE PATH "" FORCE)

# We reuse local vendored/checked-out trees; do NOT run fetch_dawn_dependencies
# (it would shell out to git against chromium.googlesource for raw SHAs).
set(DAWN_FETCH_DEPENDENCIES OFF CACHE BOOL "" FORCE)

# UWP = D3D12 only. WINDOWS_STORE=1 (from the toolchain) already turns Vulkan /
# GLFW / GL off in Dawn's CMake. Be explicit and also trim the shader toolchain
# to just the D3D12 (HLSL) path to avoid pulling glslang / spirv-tools.
set(DAWN_ENABLE_D3D11 OFF CACHE BOOL "" FORCE)
set(DAWN_ENABLE_D3D12 ON  CACHE BOOL "" FORCE)
set(DAWN_ENABLE_VULKAN OFF CACHE BOOL "" FORCE)
set(DAWN_ENABLE_DESKTOP_GL OFF CACHE BOOL "" FORCE)
set(DAWN_ENABLE_OPENGLES OFF CACHE BOOL "" FORCE)
set(DAWN_ENABLE_NULL ON CACHE BOOL "" FORCE)
set(DAWN_USE_WINDOWS_UI ON CACHE BOOL "" FORCE)

# Renderer does not serialize Tint IR, so skip the protobuf + LPM dep trees
# (also keeps third_party/protobuf, which is empty here, out of the build).
set(DAWN_BUILD_PROTOBUF OFF CACHE BOOL "" FORCE)

set(DAWN_BUILD_SAMPLES OFF CACHE BOOL "" FORCE)
set(DAWN_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(DAWN_BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
set(DAWN_BUILD_NODE_BINDINGS OFF CACHE BOOL "" FORCE)
set(DAWN_BUILD_MONOLITHIC_LIBRARY SHARED CACHE STRING "" FORCE)
set(DAWN_ENABLE_INSTALL ON CACHE BOOL "" FORCE)

set(TINT_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(TINT_BUILD_CMD_TOOLS OFF CACHE BOOL "" FORCE)
set(TINT_BUILD_SPV_READER OFF CACHE BOOL "" FORCE)
set(TINT_BUILD_SPV_WRITER OFF CACHE BOOL "" FORCE)
set(TINT_BUILD_GLSL_WRITER OFF CACHE BOOL "" FORCE)
set(TINT_BUILD_GLSL_VALIDATOR OFF CACHE BOOL "" FORCE)
set(TINT_BUILD_HLSL_WRITER ON CACHE BOOL "" FORCE)

# Dawn's D3D backend includes <DXProgrammableCapture.h> (PIX capture). The
# mingw UWP header set does not ship it. Dawn only includes the header and
# references no PIX symbols unless PIX is present, so a stub is sufficient.
# (The runtime's CMakeLists does the same for from-source Dawn on MinGW.)
set(_dx_stub_dir "${CMAKE_BINARY_DIR}/aurora_dx_stubs")
file(MAKE_DIRECTORY ${_dx_stub_dir})
file(WRITE "${_dx_stub_dir}/DXProgrammableCapture.h"
     "#pragma once\n// Stubbed PIX capture header for Dawn; no functionality when PIX isn't present.\n")
add_compile_options(-I${_dx_stub_dir})

# (No global <windows.h> force-include: it leaks the IN/OUT/OPTIONAL COM macros
#  which break Tint's std::vector<IN>, and undefing them breaks abseil's
#  stacktrace. Instead the few Dawn D3D headers that assume HRESULT/COM types
#  are available are patched to include the narrow header they need — see the
#  source edits to D3DError.h / PlatformFunctions.cpp under dependencies/dawn.)

# Use the system python (has jinja2 + markupsafe) for the code generator.
# Leave DAWN_JINJA2_DIR unset so Dawn's generator takes the system-jinja2 path.

add_subdirectory(${DAWN_ROOT} dawn EXCLUDE_FROM_ALL)
