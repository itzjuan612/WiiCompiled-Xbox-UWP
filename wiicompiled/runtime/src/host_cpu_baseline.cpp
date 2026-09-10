// Host ISA guard. Every other product target builds with -march=x86-64-v3, so a pre-Haswell
// Intel or pre-Excavator AMD machine would otherwise die on an illegal-instruction fault with no
// explanation. This TU alone skips that flag (own CMake object library, excluded from unity
// build/PCH) and runs from a priority-101 C initializer, ahead of every C++ dynamic initializer
// and thus the first AVX2 code that could execute. Keep it free of anything that could pull in
// vectorized code: no iostreams, no std::string, no runtime-wide headers.
//
// x86-64-v3 is an x86-specific optional-feature baseline (AVX2/BMI2/FMA and friends are not
// guaranteed present on every x86_64 chip); nothing here applies on AArch64, where ASIMD/NEON is
// mandatory in the base architecture and PublicProducts.cmake never applies an -march=x86-64-v3
// equivalent flag to begin with. That branch below is a no-op stub, not a port of this check.

#if defined(__x86_64__)

#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include <cpuid.h>
#if defined(_MSC_VER)
// MSVC has no GNU inline assembly, so XGETBV comes from the _xgetbv intrinsic. The file's own
// comment on the Clang path explains why the intrinsic is usually gated behind -mxsave; on MSVC
// the guard is the _MSC_VER branch below (the xgetbv instruction is only reached once CPUID has
// reported OSXSAVE). The native Clang build keeps its inline-assembly path untouched.
#include <wmmintrin.h>
#endif
#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace {

void HostCpuId(unsigned leaf, unsigned subleaf, unsigned regs[4]) {
    unsigned eax = 0, ebx = 0, ecx = 0, edx = 0;
    __cpuid_count(leaf, subleaf, eax, ebx, ecx, edx);
    regs[0] = eax;
    regs[1] = ebx;
    regs[2] = ecx;
    regs[3] = edx;
}

unsigned HostCpuIdMaxLeaf(unsigned base) {
    unsigned regs[4] = {0, 0, 0, 0};
    HostCpuId(base, 0, regs);
    return regs[0];
}

// XGETBV. Only reachable once CPUID has reported OSXSAVE.
uint64_t ReadXcr0() {
#if defined(_MSC_VER)
    // MSVC: the _xgetbv intrinsic from <wmmintrin.h>. ecx=0 selects the base XCR0 value, exactly
    // like the inline-assembly form the other toolchains use.
    const unsigned ecx = 0;
    return _xgetbv(ecx);
#else
    // The Clang/GNU driver gates the _xgetbv intrinsic behind -mxsave, which this file is
    // specifically compiled without, so use inline assembly instead.
    unsigned eax = 0, edx = 0;
    __asm__ __volatile__("xgetbv" : "=a"(eax), "=d"(edx) : "c"(0));
    return (static_cast<uint64_t>(edx) << 32) | eax;
#endif
}

struct CpuFeature {
    const char* name;
    unsigned leaf;
    unsigned subleaf;
    unsigned reg;  // index into the eax/ebx/ecx/edx array filled by HostCpuId
    unsigned bit;
    bool isOsXsave;
};

// Everything x86-64-v3 implies, which includes all of x86-64-v2. Spelled out so
// the error message can name the exact instruction sets the machine lacks
// rather than only "AVX2", which is merely the best known member of the set.
constexpr CpuFeature kRequiredFeatures[] = {
    {"SSE3", 1, 0, 2, 0, false},
    {"SSSE3", 1, 0, 2, 9, false},
    {"FMA", 1, 0, 2, 12, false},
    {"CMPXCHG16B", 1, 0, 2, 13, false},
    {"SSE4.1", 1, 0, 2, 19, false},
    {"SSE4.2", 1, 0, 2, 20, false},
    {"MOVBE", 1, 0, 2, 22, false},
    {"POPCNT", 1, 0, 2, 23, false},
    {"OSXSAVE", 1, 0, 2, 27, true},
    {"AVX", 1, 0, 2, 28, false},
    {"F16C", 1, 0, 2, 29, false},
    {"BMI1", 7, 0, 1, 3, false},
    {"AVX2", 7, 0, 1, 5, false},
    {"BMI2", 7, 0, 1, 8, false},
    {"LAHF-SAHF", 0x80000001u, 0, 2, 0, false},
    {"LZCNT", 0x80000001u, 0, 2, 5, false},
};

// Fixed-capacity text accumulation: no allocation, no exceptions, nothing that
// could route through code this file is trying to stay ahead of.
struct TextBuffer {
    char data[1024] = {};
    size_t used = 0;

    void Append(const char* text) {
        if (text == nullptr) {
            return;
        }
        while (*text != '\0' && used + 1 < sizeof(data)) {
            data[used++] = *text++;
        }
        data[used] = '\0';
    }
};

// True when the host can run this build. Otherwise `missing` holds the absent
// feature names, comma separated.
bool CollectMissingBaselineFeatures(TextBuffer& missing) {
    const unsigned maxBasic = HostCpuIdMaxLeaf(0);
    const unsigned maxExtended = HostCpuIdMaxLeaf(0x80000000u);

    bool ok = true;
    bool haveOsXsave = false;

    for (const CpuFeature& feature : kRequiredFeatures) {
        const bool leafAvailable = (feature.leaf & 0x80000000u) != 0
                                       ? feature.leaf <= maxExtended
                                       : feature.leaf <= maxBasic;

        bool present = false;
        if (leafAvailable) {
            unsigned regs[4] = {0, 0, 0, 0};
            HostCpuId(feature.leaf, feature.subleaf, regs);
            present = (regs[feature.reg] & (1u << feature.bit)) != 0;
        }

        if (present) {
            haveOsXsave = haveOsXsave || feature.isOsXsave;
            continue;
        }

        if (!ok) {
            missing.Append(", ");
        }
        missing.Append(feature.name);
        ok = false;
    }

    // CPUID reporting AVX is not sufficient: the OS also has to have enabled
    // XMM and YMM state saving or every VEX-encoded instruction faults. This is
    // the same guard a compiler's own runtime feature dispatch applies.
    if (ok && haveOsXsave) {
        constexpr uint64_t kXmmAndYmmState = 0x6u;
        if ((ReadXcr0() & kXmmAndYmmState) != kXmmAndYmmState) {
            missing.Append("operating system support for AVX register state (XCR0 YMM bits)");
            ok = false;
        }
    }

    return ok;
}

// stdio is NOT usable from a .CRT$XIC initializer - the UCRT has not stood it
// up yet, and fprintf(stderr, ...) faults there. Verified on this toolchain:
// WriteFile on the raw standard-error handle and MessageBoxA both work, printf
// does not. Anything added to this reporting path has to respect that.
//
// The POSIX path runs from an __attribute__((constructor)) instead, ahead of libc's own startup
// guarantees; ::write() on the raw fd is the same kind of allocation-free, libc-init-independent
// primitive as WriteFile is on Windows, so the same restriction is honored here.
void WriteStdErrEarly(const char* text) {
#if defined(_WIN32)
    const HANDLE handle = ::GetStdHandle(STD_ERROR_HANDLE);
    if (handle == nullptr || handle == INVALID_HANDLE_VALUE) {
        return;
    }
    size_t length = 0;
    while (text[length] != '\0') {
        ++length;
    }
    DWORD written = 0;
    ::WriteFile(handle, text, static_cast<DWORD>(length), &written, nullptr);
#else
    size_t length = 0;
    while (text[length] != '\0') {
        ++length;
    }
    (void)::write(STDERR_FILENO, text, length);
#endif
}

[[noreturn]] void ReportUnsupportedCpu(const char* missing) {
    TextBuffer message;
    message.Append(
        "This build needs a processor that supports AVX2 and the rest of the "
        "x86-64-v3 instruction set.\n\nMissing on this machine: ");
    message.Append(missing);
    message.Append(
        "\n\nx86-64-v3 covers Intel Core processors from Haswell (4th "
        "generation, 2013) onward and AMD processors from Excavator (2015) onward.");

    // The tag matches RT_TAG_RUNTIME in runtime_log.h. It is spelled out here
    // because this translation unit must not include runtime-wide headers (see
    // the file comment): runtime_log.h pulls in <iostream> and memory.h, and
    // this code runs before any C++ dynamic initializer.
    WriteStdErrEarly("[runtime] ");
    WriteStdErrEarly(message.data);
    WriteStdErrEarly("\n");

#if defined(_WIN32)
#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_DESKTOP)
    ::MessageBoxA(nullptr, message.data, "WiiCompiled - Unsupported Processor",
                  MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TASKMODAL);
#else
    // The App (Store/UWP) partition has no MessageBoxA: the WriteStdErrEarly lines above carry
    // the diagnostic to the (already-flushed) process transcript instead.
#endif
    // Leave through the OS rather than exit(): the C++ dynamic initializers
    // have not run yet, so there is no constructed program state to unwind and
    // the teardown path itself lives in AVX2 translation units.
    ::ExitProcess(1u);
#else
    // Same reasoning as the Windows path above: no C++ dynamic initializer has run yet, so
    // _exit() (skips atexit/global destructors, unlike exit()) is the correct way out.
    ::_exit(1);
#endif
}

}  // namespace

extern "C" int MkwHostCpuBaselineInit() {
    // Idempotent: on the Clang/native path this runs from the priority-101 constructor below;
    // on the MSVC/UWP path RuntimeMain (the entry point) calls it explicitly before any
    // guest/AVX2 code, because MSVC has no GNU constructor attribute and the documented
    // .CRT$XCT pre-main technique is NOT usable on the MSVC 14.44 linker (it drops the section -
    // verified: the .CRT$XCT section never reaches the OBJ/EXE and the entry never runs). Either
    // way the CPU check happens exactly once, before the runtime executes guest/AVX2 code.
    static bool ran = false;
    if (ran) {
        return 0;
    }
    ran = true;
    TextBuffer missing;
    if (!CollectMissingBaselineFeatures(missing)) {
        ReportUnsupportedCpu(missing.data);
    }
    return 0;
}

#if !defined(_MSC_VER)
// Priorities 0-100 are reserved for the implementation; 101 is the earliest a
// user constructor can request, which puts this ahead of every default-priority
// constructor in the image. (The MSVC/UWP path has no GNU constructor; RuntimeMain calls
// MkwHostCpuBaselineInit() explicitly instead - see the idempotency note on that function.)
__attribute__((constructor(101))) static void MkwHostCpuBaselineCtor() {
    MkwHostCpuBaselineInit();
}
#endif

#else  // !defined(__x86_64__)

extern "C" int MkwHostCpuBaselineInit() {
    return 0;
}

#endif  // defined(__x86_64__)
