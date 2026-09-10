# Public WiiCompiled product graph.
#
# The translator owns the translated build graph. Mario Kart's profile-neutral
# functions are compiled once into mkw_base_shared; only callers whose direct
# ABI differs between profiles receive small base/RR variants.

set(DATA_INIT_FILE "${MKW_RUNTIME_SOURCE_DIR}/../generated/data_sections_init.cpp")
set(DATA_INIT_BLOB_ASM "${MKW_RUNTIME_SOURCE_DIR}/../generated/data_sections_init_blobs.S")
if(EXISTS "${DATA_INIT_FILE}")
    list(APPEND SOURCES "${DATA_INIT_FILE}")
endif()
# Crash-report symbolization table emitted by generate-data-init. The stub
# (deliberately outside the globbed src/ tree so it is never picked up twice)
# keeps link succeeding when the generated table has not been produced yet.
set(GUEST_SYMBOL_TABLE_FILE "${MKW_RUNTIME_SOURCE_DIR}/../generated/guest_symbol_table.cpp")
if(EXISTS "${GUEST_SYMBOL_TABLE_FILE}")
    list(APPEND SOURCES "${GUEST_SYMBOL_TABLE_FILE}")
else()
    list(APPEND SOURCES "${MKW_RUNTIME_SOURCE_DIR}/cmake/guest_symbol_table_stub.cpp")
endif()
if(EXISTS "${DATA_INIT_BLOB_ASM}" AND NOT MKW_PLATFORM_UWP)
    enable_language(ASM)
    set_source_files_properties("${DATA_INIT_BLOB_ASM}" PROPERTIES LANGUAGE ASM SKIP_UNITY_BUILD_INCLUSION ON)
    list(APPEND SOURCES "${DATA_INIT_BLOB_ASM}")
endif()
list(REMOVE_DUPLICATES SOURCES)

if(MKW_PLATFORM_MACOS)
    find_library(MKW_IOKIT_FRAMEWORK IOKit REQUIRED)
    find_library(MKW_COREFOUNDATION_FRAMEWORK CoreFoundation REQUIRED)
endif()

function(mkw_apply_common_compile_options target)
    # Compiler-selected flag set (Clang: -O3 -ffast-math -w -pipe; MSVC: /O2 /w).
    target_compile_options(${target} PRIVATE ${MKW_MINGW_CLANG_FLAGS})
endfunction()

function(mkw_apply_translated_compile_options target)
    # Compiler-selected translated-shard flags (Clang: -O2 -fno-fast-math
    # -ffp-contract=off -fno-slp-vectorize -w -pipe; MSVC: /O1 /fp:precise /w).
    target_compile_options(${target} PRIVATE ${MKW_MINGW_TRANSLATED_OPTS})
endfunction()

function(mkw_configure_object_target target)
    target_include_directories(${target} PRIVATE
        "${MKW_RUNTIME_SOURCE_DIR}/include"
        "${MKW_RUNTIME_SOURCE_DIR}/src"
        # Workspace root, so translator output is spelled "generated/<x>.h"
        # instead of a ../ chain whose depth depends on the includer.
        "${MKW_RUNTIME_SOURCE_DIR}/.."
        "${MKW_RUNTIME_SOURCE_DIR}/../aurora-main/include")
    target_compile_definitions(${target} PRIVATE
        TARGET_PC)
    set_target_properties(${target} PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)
endfunction()

# Translated shard TUs are the memory-hungry compiles; everything else in the build is
# comparatively small. A dedicated Ninja job pool caps how many of them run at once so the
# global parallelism can use every core for the cheap TUs without the memory ceiling being a
# guess. The pool depth is per-machine (derived from installed RAM by LocalBuild.ps1) and is
# deliberately not part of the canonical flag set: it changes scheduling, never output bytes.
if(MKW_TRANSLATED_COMPILE_JOBS GREATER 0)
    set_property(GLOBAL APPEND PROPERTY JOB_POOLS "mkw_translated=${MKW_TRANSLATED_COMPILE_JOBS}")
endif()

function(mkw_bound_translated_compiles target)
    if(MKW_TRANSLATED_COMPILE_JOBS GREATER 0)
        set_property(TARGET ${target} PROPERTY JOB_POOL_COMPILE mkw_translated)
    endif()
endfunction()

function(mkw_configure_translated_target target)
    mkw_configure_object_target(${target})
    mkw_apply_translated_compile_options(${target})
    mkw_bound_translated_compiles(${target})
endfunction()

add_library(mkw_runtime_common OBJECT ${SOURCES})
mkw_configure_object_target(mkw_runtime_common)
target_compile_features(mkw_runtime_common PRIVATE cxx_std_20)
target_compile_definitions(mkw_runtime_common PRIVATE
    SDL_MAIN_HANDLED
    _DISABLE_STRING_ANNOTATION _DISABLE_VECTOR_ANNOTATION)
target_link_libraries(mkw_runtime_common PRIVATE
    aurora::gx aurora::pad aurora::si aurora::vi aurora::mtx)
target_link_libraries(mkw_runtime_common PRIVATE mkw_platform mkw::pugixml mkw::toml11 mkw::cryptopp)
if(MKW_PLATFORM_WINDOWS)
    target_link_libraries(mkw_runtime_common PRIVATE shell32 windowsapp)
elseif(MKW_PLATFORM_LINUX)
    # ${CMAKE_DL_LIBS} for music_attenuation.cpp's dlopen of libdbus-1 (MPRIS
    # media monitoring). Empty string on glibc >= 2.34 where dl* is in libc.
    target_link_libraries(mkw_runtime_common PRIVATE mkw::libco ${CMAKE_DL_LIBS})
endif()
if(MKW_CPPWINRT_INCLUDE_DIR)
    if(NOT EXISTS "${MKW_CPPWINRT_INCLUDE_DIR}/winrt/base.h")
        message(FATAL_ERROR
            "MKW_CPPWINRT_INCLUDE_DIR does not contain winrt/base.h: ${MKW_CPPWINRT_INCLUDE_DIR}")
    endif()
    target_include_directories(mkw_runtime_common PRIVATE "${MKW_CPPWINRT_INCLUDE_DIR}")
endif()

# Keep runtime unity units small and semantically related. The old generated-TU
# batch size put all 57 native runtime sources into one memory-heavy compiler job.
foreach(source IN LISTS SOURCES)
    get_filename_component(source_name "${source}" NAME_WE)
    string(REPLACE "\\" "/" source_normalized "${source}")
    if(source_normalized MATCHES "/hle/gx/")
        set(runtime_group "gx_bridge")
    elseif(source_name MATCHES "network|socket|dns|dwc|ios")
        set(runtime_group "network_ios")
    elseif(source_name MATCHES "os_|system|memory|fiber|scheduler")
        set(runtime_group "guest_system")
    elseif(source_name MATCHES "debug|trace|prof")
        set(runtime_group "diagnostics")
    else()
        string(SHA256 source_hash "${source_name}")
        string(SUBSTRING "${source_hash}" 0 4 source_hash_prefix)
        math(EXPR runtime_bucket "0x${source_hash_prefix} % 8")
        set(runtime_group "runtime_${runtime_bucket}")
    endif()
    set_source_files_properties("${source}" PROPERTIES UNITY_GROUP "${runtime_group}")
endforeach()
# These translation units implement guest-visible floating-point bit
# semantics.  Keep them out of the fast-math runtime unity groups and apply
# the same contraction/rounding policy as translated PPC shards.
set(MKW_PPC_SEMANTIC_RUNTIME_SOURCES
    "${MKW_RUNTIME_SOURCE_DIR}/src/ppc_helpers.cpp"
    "${MKW_RUNTIME_SOURCE_DIR}/src/fpu_helpers.cpp")
# Compiler-selected FP options (Clang: -fno-fast-math -ffp-contract=off; MSVC:
# /fp:precise). COMPILE_OPTIONS joins the list into the Ninja FLAGS line, so it
# reaches the compiler as separate tokens — same mechanism as the original.
set_source_files_properties(${MKW_PPC_SEMANTIC_RUNTIME_SOURCES} PROPERTIES
    SKIP_UNITY_BUILD_INCLUSION ON
    SKIP_PRECOMPILE_HEADERS ON
    COMPILE_OPTIONS "${MKW_MINGW_FP_OPTIONS}")
set_target_properties(mkw_runtime_common PROPERTIES UNITY_BUILD ON UNITY_BUILD_MODE GROUP)
target_precompile_headers(mkw_runtime_common PRIVATE "${MKW_RUNTIME_SOURCE_DIR}/include/mkw_pch.h")
mkw_apply_common_compile_options(mkw_runtime_common)

# UWP (Option B): the generated AT&T data blob must not ride inside
# mkw_runtime_common. CMake's target_compile_options is not language-scoped, so
# the MSVC-only C/C++ flags applied above (/O2 /w, /arch:AVX2) would also be
# handed to the ASM compiler - which on this target is the UWP Clang wrapper,
# and it rejects MSVC flags as file operands ("no such file or directory:
# '/O2'"). The blob is pure data (.rdata + .incbin + .globl, no directives),
# so optimization/arch flags are irrelevant to its object bytes; it only needs
# the defines/includes, which CMake already passes per-compiler (-D for Clang)
# via the directory scope and CMAKE_C_FLAGS. Give it a dedicated ASM object
# target that receives no raw compile options, and inject its object into the
# products from mkw_configure_product below. Native (Clang) keeps the blob in
# mkw_runtime_common exactly as before - this branch is UWP-only.
if(EXISTS "${DATA_INIT_BLOB_ASM}" AND MKW_PLATFORM_UWP)
    enable_language(ASM)
    add_library(mkw_data_init_blob OBJECT "${DATA_INIT_BLOB_ASM}")
    set_source_files_properties("${DATA_INIT_BLOB_ASM}" PROPERTIES
        LANGUAGE ASM SKIP_UNITY_BUILD_INCLUSION ON)
    # Deliberately no target_compile_options: no /O, no /w, no /arch:AVX2.
    # The blob is self-contained (absolute .incbin paths, .rdata only) so
    # optimization/arch flags are irrelevant to its object bytes, and the ASM
    # compiler is the Clang wrapper which rejects the MSVC flag forms.
    # Directory-scope definitions/includes are inherited automatically and
    # harmlessly adapted to the ASM compiler.
endif()

# Host ISA guard. Windows and Linux x86_64 product targets use x86-64-v3, so
# this object deliberately keeps the plain baseline ISA and checks the CPU
# before any AVX2/FMA code can execute. AArch64 has no equivalent optional ISA
# floor to probe: NEON/FMA are architectural requirements.
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(AMD64|amd64|x86_64|X86_64)$")
    add_library(mkw_cpu_baseline OBJECT "${MKW_CPU_BASELINE_SOURCE}")
    target_compile_features(mkw_cpu_baseline PRIVATE cxx_std_17)
    set_target_properties(mkw_cpu_baseline PROPERTIES UNITY_BUILD OFF)
    # Warning suppression only — the baseline-ISA guard object must NOT receive
    # the -O/-march flags (that is what keeps it on the baseline ISA).
    target_compile_options(mkw_cpu_baseline PRIVATE ${MKW_MINGW_NO_WARN})
endif()

if(NOT MKW_BASE_COMMON_SHARDS)
    message(FATAL_ERROR "Translator build graph contains no shared base shards")
endif()

add_library(mkw_base_shared STATIC ${MKW_BASE_COMMON_SHARDS})
mkw_configure_translated_target(mkw_base_shared)
target_precompile_headers(mkw_base_shared PRIVATE "${MKW_RUNTIME_SOURCE_DIR}/include/mkw_pch.h")

if(MKW_BASE_PORTABLE_SENSITIVE_SHARDS)
    add_library(mkw_base_sensitive OBJECT ${MKW_BASE_PORTABLE_SENSITIVE_SHARDS})
    mkw_configure_translated_target(mkw_base_sensitive)
    target_precompile_headers(mkw_base_sensitive REUSE_FROM mkw_base_shared)
endif()

if(MKW_HAVE_RETRO_REWIND)
    if(MKW_RETRO_PORTABLE_SENSITIVE_SHARDS)
        add_library(mkw_retro_sensitive OBJECT ${MKW_RETRO_PORTABLE_SENSITIVE_SHARDS})
        mkw_configure_translated_target(mkw_retro_sensitive)
        target_precompile_headers(mkw_retro_sensitive REUSE_FROM mkw_base_shared)
    endif()

    set(MKW_RETRO_BLOB_OBJECTS)
    set(MKW_RETRO_TRANSLATED_SOURCES ${MKW_RETRO_MOD_SHARDS})
    foreach(source IN LISTS MKW_RETRO_EXTRA_SOURCES)
        if(source MATCHES "\\.S$")
            enable_language(ASM)
            set_source_files_properties("${source}" PROPERTIES
                LANGUAGE ASM SKIP_PRECOMPILE_HEADERS ON SKIP_UNITY_BUILD_INCLUSION ON)
            if(MKW_PLATFORM_UWP)
                # UWP: the ASM compiler is the Clang wrapper, which rejects the
                # MSVC-only C/C++ flags applied to mkw_retro_rewind_functions
                # ("no such file or directory: '/O2'"). Compile the data blob in
                # its own option-free object target, exactly as the base product
                # does with mkw_data_init_blob, and inject it into RetroRewind.
                get_filename_component(blob_name "${source}" NAME_WE)
                add_library(mkw_retro_blob_${blob_name} OBJECT "${source}")
                list(APPEND MKW_RETRO_BLOB_OBJECTS
                    $<TARGET_OBJECTS:mkw_retro_blob_${blob_name}>)
            else()
                list(APPEND MKW_RETRO_TRANSLATED_SOURCES "${source}")
            endif()
        else()
            list(APPEND MKW_RETRO_TRANSLATED_SOURCES "${source}")
        endif()
    endforeach()
    add_library(mkw_retro_rewind_functions OBJECT ${MKW_RETRO_TRANSLATED_SOURCES})
    mkw_configure_translated_target(mkw_retro_rewind_functions)
    target_precompile_headers(mkw_retro_rewind_functions REUSE_FROM mkw_base_shared)
endif()

function(mkw_configure_product target)
    target_sources(${target} PRIVATE $<TARGET_OBJECTS:mkw_runtime_common>)
    # UWP: the guest data blob was moved out of mkw_runtime_common (see above)
    # so the MSVC C/C++ compile options do not reach the Clang ASM wrapper.
    # Native builds have no mkw_data_init_blob target; the blob stays in
    # mkw_runtime_common there.
    if(TARGET mkw_data_init_blob)
        target_sources(${target} PRIVATE $<TARGET_OBJECTS:mkw_data_init_blob>)
    endif()
    # Startup CPU check. Must stay a separate object library so it keeps the
    # plain baseline ISA while everything around it is built for x86-64-v3.
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(AMD64|amd64|x86_64|X86_64)$")
        target_sources(${target} PRIVATE $<TARGET_OBJECTS:mkw_cpu_baseline>)
    endif()
    target_include_directories(${target} PRIVATE
        "${MKW_RUNTIME_SOURCE_DIR}/include"
        "${MKW_RUNTIME_SOURCE_DIR}/src"
        # Workspace root, so translator output is spelled "generated/<x>.h"
        # instead of a ../ chain whose depth depends on the includer.
        "${MKW_RUNTIME_SOURCE_DIR}/.."
        "${MKW_RUNTIME_SOURCE_DIR}/../aurora-main/include")
    target_compile_definitions(${target} PRIVATE
        SDL_MAIN_HANDLED _DISABLE_STRING_ANNOTATION _DISABLE_VECTOR_ANNOTATION TARGET_PC)
    target_compile_features(${target} PRIVATE cxx_std_20)
    mkw_apply_common_compile_options(${target})
    # The dispatch-table and registration shards compile inside the product target itself and
    # include the same fat translated headers; bound them by the same pool.
    mkw_bound_translated_compiles(${target})
    target_link_libraries(${target} PRIVATE
        mkw_platform mkw_base_shared mkw::pugixml mkw::toml11 mkw::cryptopp)

    target_link_libraries(${target} PRIVATE
        aurora::gx aurora::pad aurora::si aurora::vi aurora::mtx)
    if(MKW_PLATFORM_MACOS)
        target_link_libraries(${target} PRIVATE
            "${MKW_IOKIT_FRAMEWORK}" "${MKW_COREFOUNDATION_FRAMEWORK}")
    endif()
    if(EXISTS "${MKW_AURORA_DIR}/cmake/AuroraCopyRuntimeDLLs.cmake")
        include("${MKW_AURORA_DIR}/cmake/AuroraCopyRuntimeDLLs.cmake")
        aurora_copy_runtime_dlls(${target})
    endif()
    if(TARGET sqlite3)
        get_target_property(MKW_SQLITE_TARGET_TYPE sqlite3 TYPE)
    endif()
    if(TARGET sqlite3 AND
       (MKW_SQLITE_TARGET_TYPE STREQUAL "SHARED_LIBRARY" OR
        MKW_SQLITE_TARGET_TYPE STREQUAL "MODULE_LIBRARY"))
        add_custom_command(TARGET ${target} POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:sqlite3> $<TARGET_FILE_DIR:${target}>)
    endif()

    if(MKW_PLATFORM_WINDOWS)
        target_link_libraries(${target} PRIVATE
            dbghelp user32 winmm ws2_32 iphlpapi secur32 crypt32 windowsapp)
        # UWP (Option B) renders through Dawn's D3D12 backend on a CoreWindow:
        # link the D3D12/DXGI import libs the product pulls in via aurora/dawn.
        if(MKW_PLATFORM_UWP)
            target_link_libraries(${target} PRIVATE d3d12 dxgi d3dcompiler)
        endif()

        set_target_properties(${target} PROPERTIES WIN32_EXECUTABLE TRUE)
        # UWP diagnostics: the Release objects carry no debug info, so cdb stacks
        # from a live parked process resolve only to raw offsets. /DEBUG emits a
        # public-symbols PDB and /MAP a full symbol+offset map - both link-only,
        # no object recompilation.
        if(MKW_PLATFORM_UWP AND MSVC)
            target_link_options(${target} PRIVATE /DEBUG /MAP)
        endif()
    elseif(MKW_PLATFORM_LINUX)
        # mkw_runtime_common is an OBJECT library: WiiCompiled/RetroRewind only pull in its .o
        # files via $<TARGET_OBJECTS:>, which does not propagate mkw_runtime_common's own
        # target_link_libraries (object libraries don't carry usage requirements to a consumer
        # that isn't itself linked against as a target). fiber_manager.cpp's co_* calls live in
        # those objects, so the actual executable link needs mkw::libco directly, same as it
        # needs it independently of that first `if(WIN32)` branch above. ${CMAKE_DL_LIBS} is
        # here for the same reason: music_attenuation.cpp's dlopen(libdbus-1) lives in those
        # objects (empty string on glibc >= 2.34, where dl* is in libc).
        target_link_libraries(${target} PRIVATE mkw::libco ${CMAKE_DL_LIBS})
    endif()
    if(MKW_PLATFORM_WINDOWS AND NOT MKW_PLATFORM_UWP)
        # llvm-mingw (native) runtime DLLs. MSVC uses its own CRT
        # (VCRUNTIME140.dll, shipped in the UWP/Xbox runtime), so skip these.
        foreach(runtime_dll libc++.dll libunwind.dll)
            execute_process(
                COMMAND "${CMAKE_CXX_COMPILER}" "--print-file-name=${runtime_dll}"
                OUTPUT_VARIABLE runtime_dll_path
                OUTPUT_STRIP_TRAILING_WHITESPACE)
            if(NOT EXISTS "${runtime_dll_path}")
                get_filename_component(mkw_compiler_bin "${CMAKE_CXX_COMPILER}" DIRECTORY)
                set(runtime_dll_path "${mkw_compiler_bin}/${runtime_dll}")
            endif()
            if(NOT EXISTS "${runtime_dll_path}")
                message(FATAL_ERROR "llvm-mingw runtime DLL not found: ${runtime_dll}")
            endif()
            add_custom_command(TARGET ${target} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${runtime_dll_path}" $<TARGET_FILE_DIR:${target}>)
        endforeach()
    endif()

    set(MKW_WII_BOOTSTRAP_SOURCE_DIR "${MKW_RUNTIME_SOURCE_DIR}/assets/wii")
    if(NOT EXISTS "${MKW_WII_BOOTSTRAP_SOURCE_DIR}/shared2/wc24")
        message(FATAL_ERROR "Missing Wii first-run bootstrap payload: ${MKW_WII_BOOTSTRAP_SOURCE_DIR}")
    endif()
    add_custom_command(TARGET ${target} POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${MKW_WII_BOOTSTRAP_SOURCE_DIR}" "$<TARGET_FILE_DIR:${target}>/wii_bootstrap")

    set(MKW_DSP_COEFFICIENT_ROM "${MKW_RUNTIME_SOURCE_DIR}/assets/dsp/dsp_coef.bin")
    if(NOT EXISTS "${MKW_DSP_COEFFICIENT_ROM}")
        message(FATAL_ERROR "Missing Wii DSP coefficient ROM: ${MKW_DSP_COEFFICIENT_ROM}")
    endif()
    file(SHA256 "${MKW_DSP_COEFFICIENT_ROM}" MKW_DSP_COEFFICIENT_ROM_SHA256)
    if(NOT MKW_DSP_COEFFICIENT_ROM_SHA256 STREQUAL
       "d7741279c2e8ec5c5fb318f8fbdd6de6bf583520d288e836a5383233a4238179")
        message(FATAL_ERROR "Wii DSP coefficient ROM hash mismatch: ${MKW_DSP_COEFFICIENT_ROM_SHA256}")
    endif()
    add_custom_command(TARGET ${target} POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${MKW_DSP_COEFFICIENT_ROM}" "$<TARGET_FILE_DIR:${target}>/dsp_coef.bin")

    # Aurora imports this portable recipe database into each user's writable
    # pipeline cache. Keep the upstream filename so its default resourcesPath
    # lookup works without application-specific configuration.
    set(MKW_INITIAL_PIPELINE_CACHE
        "${MKW_RUNTIME_SOURCE_DIR}/assets/pipeline/initial_pipeline_cache.db")
    if(NOT EXISTS "${MKW_INITIAL_PIPELINE_CACHE}")
        message(FATAL_ERROR "Missing transferable Aurora pipeline cache: ${MKW_INITIAL_PIPELINE_CACHE}")
    endif()
    add_custom_command(TARGET ${target} POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${MKW_INITIAL_PIPELINE_CACHE}"
        "$<TARGET_FILE_DIR:${target}>/initial_pipeline_cache.db")
endfunction()

add_executable(WiiCompiled "${MKW_BASE_PRODUCT_SOURCE}" ${MKW_BASE_REGISTRATION_SOURCES})
mkw_configure_product(WiiCompiled)
target_precompile_headers(WiiCompiled PRIVATE
    "${MKW_RUNTIME_SOURCE_DIR}/include/mkw_pch.h")
if(TARGET mkw_base_sensitive)
    target_sources(WiiCompiled PRIVATE $<TARGET_OBJECTS:mkw_base_sensitive>)
endif()

# UWP (Option B, MSVC): the C++/CX app entry stub. This is the ONLY
# C++/CX source in the product, so it is compiled as a standalone OBJECT
# library with /ZW /std:c++14 (C++/CX requires the C++14 front end; the
# product itself stays C++20 without /ZW) instead of being added to the
# C++20 product sources. Flags mirror the SDL-uwp fork's own winrt TUs
# (SDL-uwp/CMakeLists.txt 521-523: /ZW + std:c++14); the global UWP
# defines and /AI metadata dirs come from the toolchain's
# CMAKE_CXX_FLAGS, which OBJECT libraries inherit. The stub object must
# NOT get the product PCH (mkw_pch.h is not C++/CX-clean).
if(MKW_PLATFORM_UWP AND MSVC)
    add_library(mkw_winrt_main_stub OBJECT
        "${MKW_RUNTIME_SOURCE_DIR}/src/winrt_main_stub.cpp")
    target_compile_options(mkw_winrt_main_stub PRIVATE /ZW -std:c++14)
    # SDL3/SDL_main.h (SDL_RunApp declaration): the stub does not link the SDL
    # targets, so it does not inherit their INTERFACE include dirs. Mirror the
    # two dirs every SDL-consuming compile line already gets (verified in the
    # generated build.ninja): the fork's own include tree and SDL's generated
    # SDL_revision.h dir (exists by now: add_subdirectory(aurora) ran above).
    target_include_directories(mkw_winrt_main_stub PRIVATE
        "${MKW_RUNTIME_SOURCE_DIR}/../Launcher/artifacts/dependencies/SDL-uwp/include"
        "${CMAKE_BINARY_DIR}/_deps/sdl-build/include-revision")
    set_target_properties(mkw_winrt_main_stub PROPERTIES
        COMPILE_PDB_NAME "mkw_winrt_main_stub"
        UNITY_BUILD OFF)
    target_sources(WiiCompiled PRIVATE $<TARGET_OBJECTS:mkw_winrt_main_stub>)
endif()

if(MKW_HAVE_RETRO_REWIND)
    add_executable(RetroRewind "${MKW_RETRO_REWIND_PRODUCT_SOURCE}" ${MKW_RETRO_REGISTRATION_SOURCES})
    mkw_configure_product(RetroRewind)
    target_precompile_headers(RetroRewind REUSE_FROM WiiCompiled)
    if(TARGET mkw_retro_sensitive)
        target_sources(RetroRewind PRIVATE $<TARGET_OBJECTS:mkw_retro_sensitive>)
    endif()
    target_sources(RetroRewind PRIVATE $<TARGET_OBJECTS:mkw_retro_rewind_functions>)
    if(MKW_RETRO_BLOB_OBJECTS)
        target_sources(RetroRewind PRIVATE ${MKW_RETRO_BLOB_OBJECTS})
    endif()
    # UWP: RetroRewind is a second packaged executable and needs the same C++/CX
    # CoreWindow entry stub the base product gets above (it is a per-executable
    # entry point, so it cannot be shared as an interface).
    if(TARGET mkw_winrt_main_stub)
        target_sources(RetroRewind PRIVATE $<TARGET_OBJECTS:mkw_winrt_main_stub>)
    endif()
    add_custom_target(mkw_release DEPENDS WiiCompiled RetroRewind)
else()
    add_custom_target(mkw_release DEPENDS WiiCompiled)
    message(STATUS "RetroRewind target disabled (run translate-mod and emit-build-shards)")
endif()

# Windows and Linux x86_64 share the x86-64-v3 floor that the CPU baseline
# object above checks. AArch64 builds are compiled locally for the host that
# will run them, so both Linux and Apple Silicon use the compiler's native CPU
# tuning rather than leaving target-specific performance on the table.
# Compiler-selected: Clang -march=x86-64-v3; MSVC /arch:AVX2 (closest match).
set(MKW_BASELINE_ARCH_FLAG "${MKW_MINGW_ARCH_FLAG}")

set(MKW_ALL_BUILD_TARGETS
    mkw_runtime_common mkw_base_shared mkw_base_sensitive mkw_retro_sensitive
    mkw_retro_rewind_functions WiiCompiled RetroRewind)
foreach(target IN LISTS MKW_ALL_BUILD_TARGETS)
    if(TARGET ${target} AND MKW_BASELINE_ARCH_FLAG)
        target_compile_options(${target} PRIVATE ${MKW_BASELINE_ARCH_FLAG})
    endif()
endforeach()
