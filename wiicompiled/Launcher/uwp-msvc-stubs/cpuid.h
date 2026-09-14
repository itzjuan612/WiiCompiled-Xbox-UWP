// cpuid.h — UWP/MSVC stub (Option B). The pinned Clang/llvm-mingw toolchain ships a
// <cpuid.h> that defines __cpuid_count (GCC/Clang spelling); MSVC ships NO <cpuid.h> at
// all, and its <intrin.h> only provides __cpuid / __cpuidex. host_cpu_baseline.cpp
// includes <cpuid.h> and calls __cpuid_count, so this stub (found first via the /I
// stubs dir that precedes the SDK on the UWP include path) bridges the spelling.
// C- and C++-compatible; a no-op where the real header already provides the name.
#ifndef _MKW_STUB_CPUID_H
#define _MKW_STUB_CPUID_H

#if defined(_MSC_VER)
#include <intrin.h>
#ifndef __cpuid_count
// GCC/Clang: void __cpuid_count(unsigned int leaf, unsigned int subleaf,
//                               unsigned int* eax, unsigned int* ebx,
//                               unsigned int* ecx, unsigned int* edx);
// MSVC:       void __cpuidex(int* cpuInfo, int leaf, int subleaf);
static inline void __cpuid_count(unsigned int leaf, unsigned int subleaf,
                                 unsigned int* eax, unsigned int* ebx,
                                 unsigned int* ecx, unsigned int* edx) {
    int buf[4] = {0, 0, 0, 0};
    __cpuidex(buf, (int)leaf, (int)subleaf);
    if (eax) *eax = (unsigned int)buf[0];
    if (ebx) *ebx = (unsigned int)buf[1];
    if (ecx) *ecx = (unsigned int)buf[2];
    if (edx) *edx = (unsigned int)buf[3];
}
#endif
#endif  // _MSC_VER

#endif  // _MKW_STUB_CPUID_H
