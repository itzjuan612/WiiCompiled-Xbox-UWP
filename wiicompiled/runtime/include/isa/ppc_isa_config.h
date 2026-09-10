#pragma once

#include <atomic>
#include <cstdint>

#if defined(_MSC_VER)
// MSVC 14.44 exploits __restrict on the generated functions' ctx parameter to sink the
// `ctx->gpr[N] = rN` store blocks past the InvokeDirectCpu dispatch call: func_8007B220
// (Picture::DrawSelf) emitted the DrawQuad argument stores only in its epilogue, so the
// native DrawQuad bridge read GetVtxPos's stale r3/r4 return values (a float bit pattern
// as a pointer -> AV in EmitLytDrawQuad). The generated functions genuinely pass ctx to
// opaque callees that read/write it, so the restrict contract is unsound under MSVC's
// reordering rules. Clang (native build) handles the same pattern correctly and keeps the hint.
#define MKW_RESTRICT
#else
#define MKW_RESTRICT __restrict
#endif
#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>
#elif defined(__aarch64__)
#include <arm_neon.h>
#else
#error "ppc_isa_config.h has no SIMD intrinsics header for this architecture"
#endif

inline constexpr bool MkwStateFreeAbiEnabled(uint32_t) noexcept
{
    return true;
}

#if defined(_WIN32)
#define MKW_PPC_FORCE_INLINE __forceinline
#define MKW_PPC_NO_INLINE __declspec(noinline)
#if defined(_MSC_VER)
// MSVC has no __regcall (a Clang keyword): it is a register-call hint the interpreter uses to
// shave register args, not a correctness feature - an empty define is a plain call, which is
// exactly what the non-Windows branch already does. No first-party/generated source actually
// expands this (verified zero uses in the 29065 shards + runtime), so empty is safe.
#define MKW_PPC_INTERNAL_CALL
#else
// Clang targeting Windows (native build) understands __regcall.
#define MKW_PPC_INTERNAL_CALL __regcall
#endif
#else
// __forceinline/__declspec are MS-extension keywords Clang only recognizes when targeting
// Windows (MSVC or mingw); native Linux Clang needs the GNU-attribute spellings instead.
// __regcall has no portable non-Windows equivalent worth chasing here - the extra register
// args it saves matter for the hot PPC interpreter loop on Windows, but plain calls are fine
// elsewhere.
#define MKW_PPC_FORCE_INLINE __attribute__((always_inline)) inline
#define MKW_PPC_NO_INLINE __attribute__((noinline))
#define MKW_PPC_INTERNAL_CALL
#endif

#if defined(_MSC_VER)
// MSVC has no GNU __attribute__((always_inline)). Historically this was `inline`, but in a large
// TU MSVC does NOT emit a symbol for an `extern "C" inline` function that is only defined there
// and never called (the defining shard object then lacks the _statefree_vN export and every
// cross-TU caller LNK2019s - observed: build14 left 37 func_80xxxxxx_statefree_vN unresolved
// while the native Clang objects emit strong `T` symbols for the same functions). Each statefree
// symbol is defined in exactly ONE shard (audited: 0 multi-definition), so a plain non-inline
// `extern "C"` definition is unambiguous and emits a strong symbol - the same shape the Clang
// branch produces via always_inline. Verified with the sf_fix probe (uwp-smoke/sf_fix_*.cpp):
// plain definition + cross-TU call links and the 16-byte 2-lane struct-return ABI is intact
// (l0/l1 lanes arrive correctly). Cost: the 70 statefree helpers lose forced inlining on MSVC
// (perf, not correctness); revisit if profiling ever demands it.
#define MKW_PPC_ALWAYS_INLINE_BODY
// MSVC has no __attribute__((cold)): the cold-placement hint is a perf nicety, not correctness.
// Left empty so it composes cleanly with the __declspec(noinline) it is always paired with in
// ppc_isa_quantized.h (MKW_PPC_NO_INLINE MKW_PPC_COLD inline ...).
#define MKW_PPC_COLD
// The 2-lane statefree result: on Clang this is a 16-byte GCC extended vector (two uint64 lanes).
// MSVC's __m128i is an *opaque* type - it cannot be brace-initialized from {u64, u64} (the
// generated `return { cached_r0, cached_r3 };`) nor indexed with [0]/[1] (1260 generated uses) -
// so it is NOT a drop-in. Use a 16-byte aggregate of two uint64 lanes with operator[], which
// matches both the Clang layout (two 64-bit lanes) and the exact generated-code operations.
struct MkwStateFreeResult2 {
    uint64_t lane[2];
    uint64_t& operator[](unsigned index) { return lane[index]; }
    const uint64_t& operator[](unsigned index) const { return lane[index]; }
};
#else
#define MKW_PPC_ALWAYS_INLINE_BODY __attribute__((always_inline))
#define MKW_PPC_COLD __attribute__((cold))
using MkwStateFreeResult2 = uint64_t __attribute__((ext_vector_type(2)));
#endif
