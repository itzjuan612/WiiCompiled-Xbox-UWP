// msvc_builtin_compat.h — MSVC-only preprocessor/intrinsic parity shim.
//
// The WiiCompiled runtime and the vendored Aurora tree were written against the
// pinned Clang/llvm-mingw toolchain. On x86-64, Clang pre-defines the arch
// macro `__x86_64__` and provides the `__builtin_*` intrinsic family
// (__builtin_clz/ctz/bswap*/rotateleft*/popcount/constant_p). MSVC does NEITHER:
// it defines `_M_X64`/`_M_AMD64` and has no `__builtin_*`.
//
// The shared sources gate their x86 SSE/ISA paths on `#if defined(__x86_64__)`
// (the runtime/include/isa/* headers, host_cpu_baseline.cpp, guest_flat_memory.h,
// ...) and call the `__builtin_*` intrinsics. This shim, force-included (/FI) for
// the UWP (Option B) MSVC build only, makes MSVC present the *same* environment:
//   * `__x86_64__` / `__aarch64__` defined to match the host arch, and
//   * the `__builtin_*` functions provided as MSVC-intrinsic shims.
// So the same sources compile unchanged on both toolchains. The native Clang
// build never includes this header (it is wired only into UWPToolchainMSVC.cmake),
// and every shim here is a no-op where MSVC already defines the symbol, so it is
// safe to force-include into every MSVC C/CXX TU (Dawn/abseil/zstd/etc.).
#ifndef MKW_MSVB_BUILTIN_COMPAT_H
#define MKW_MSVB_BUILTIN_COMPAT_H

#ifdef _MSC_VER

// --- 1) NO architecture-macro parity (deliberately) --------------------------
// This shim used to #define __x86_64__ for MSVC, but that is HARMFUL: it force-included into
// every TU, it makes vendored abseil/cryptopp take their `#if defined(__x86_64__)`
// GCC/Clang branches (GNU __asm__ rdtsc/cpuid, etc.) which MSVC cannot compile, even though
// those same libraries ship correct native-MSVC branches keyed on _M_X64 (e.g.
// absl unscaledcycleclock.cc:124 `#elif defined(_M_X64)` -> __rdtsc()). MSVC natively defines
// _M_X64 (and _M_ARM64), so first-party code that needs the x86-64 path keys on _M_X64 directly
// (runtime/include/isa/*, guest_flat_memory.h, host_cpu_baseline.cpp, main.cpp all check
// `defined(__x86_64__) || defined(_M_X64)`); the native Clang build keeps __x86_64__ and is
// unaffected. Do NOT reintroduce the arch-macro defines here.

#if defined(_M_X64) || defined(_M_ARM64)
#include <intrin.h>
#include <stdlib.h>
// NB: no <cpuid.h> include here. MSVC ships no <cpuid.h> (and no __cpuid_count); the UWP
// include path has a stub <cpuid.h> (see cpuid.h in this stubs dir) that bridges
// __cpuid_count -> __cpuidex, and host_cpu_baseline.cpp includes it directly. Force-including
// it here would break every TU (C1083) since the name is only needed by that one file.

// --- 2) Leading/trailing zero + popcount ------------------------------------
// MSVC's __lzcnt/__tzcnt are undefined on 0 input; the _BitScan* family is
// well-defined (returns 0 when no bit is set). We fold the 0-case explicitly so
// the shims match GCC's "0 => all zeros/ones" convention the callers rely on.
static inline unsigned mkw_msvc_clz32u(unsigned x)
{
  unsigned long i = 0;
  return _BitScanReverse(&i, x) ? (unsigned)(31u - i) : 32u;
}
static inline unsigned mkw_msvc_clz64u(unsigned long long x)
{
  unsigned long i = 0;
  return _BitScanReverse64(&i, x) ? (unsigned)(63u - i) : 64u;
}
static inline unsigned mkw_msvc_ctz32u(unsigned x)
{
  unsigned long i = 0;
  return _BitScanForward(&i, x) ? i : 32u;
}
static inline unsigned mkw_msvc_ctz64u(unsigned long long x)
{
  unsigned long i = 0;
  return _BitScanForward64(&i, x) ? i : 64u;
}
static inline unsigned mkw_msvc_popcount32u(unsigned x)
{
  return (unsigned)__popcnt(x);  // POPCNT is guaranteed under /arch:AVX2
}

// MSVC defines none of these (verified: cl reports C3861 for each), so the
// #defines cannot collide with a pre-existing definition.
#ifndef __builtin_clz
#define __builtin_clz(x)   ((int)mkw_msvc_clz32u((unsigned)(x)))
#endif
#ifndef __builtin_clzll
#define __builtin_clzll(x) ((int)mkw_msvc_clz64u((unsigned long long)(x)))
#endif
#ifndef __builtin_ctz
#define __builtin_ctz(x)   ((int)mkw_msvc_ctz32u((unsigned)(x)))
#endif
#ifndef __builtin_ctzll
#define __builtin_ctzll(x) ((int)mkw_msvc_ctz64u((unsigned long long)(x)))
#endif
#ifndef __builtin_popcount
#define __builtin_popcount(x) ((int)mkw_msvc_popcount32u((unsigned)(x)))
#endif
#ifndef __builtin_constant_p
#define __builtin_constant_p(x) 0  // no MSVC analogue; "runtime value" is the safe fallback
#endif

// --- 3) Byte-swap + rotate --------------------------------------------------
// Byte-swap: the UCRT declares _byteswap_ushort/_ulong/_uint64 in <stdlib.h>
// (stdlib.h:298-300). The _byteswap_16/32/64 spellings are MSVC-internal
// intrin.h names NOT in the public SDK, so map to the UCRT ones.
// Rotate: _rotl/_rotl64 are the MSVC rotate intrinsics (intrin.h), function-like macros.
#ifndef __builtin_bswap16
#define __builtin_bswap16(x) _byteswap_ushort((unsigned short)(x))
#endif
#ifndef __builtin_bswap32
#define __builtin_bswap32(x) _byteswap_ulong((unsigned)(x))
#endif
#ifndef __builtin_bswap64
#define __builtin_bswap64(x) _byteswap_uint64((unsigned __int64)(x))
#endif
#ifndef __builtin_rotateleft32
#define __builtin_rotateleft32(x, n) _rotl((unsigned)(x), (unsigned)(n))
#endif
#ifndef __builtin_rotateleft64
#define __builtin_rotateleft64(x, n) _rotl64((unsigned long long)(x), (unsigned)(n))
#endif
#ifndef __builtin_rotateleft16
#define __builtin_rotateleft16(x, n) _rotl16((unsigned short)(x), (unsigned)(n))
#endif

#endif  // _M_X64 || _M_ARM64
#endif  // _MSC_VER
#endif  // MKW_MSVB_BUILTIN_COMPAT_H
