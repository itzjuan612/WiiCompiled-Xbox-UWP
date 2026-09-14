// UWP-only stub of dbghelp.h (Store API partition).
//
// The real SDK dbghelp.h (um) gates every Sym*/MiniDump/StackWalk API under
//   WINAPI_FAMILY_PARTITION(DESKTOP | PKG_WER)
// and even the types it needs (SYMBOL_INFO, IMAGEHLP_SYMBOL64,
// IMAGEHLP_LINE64) sit behind (DESKTOP | GAMES). Under
// WINAPI_FAMILY=WINAPI_FAMILY_APP (this whole UWP/Xbox binary) all of that
// compiles out, so three consumers fail:
//   * absl/debugging/symbolize_win32.inc   (abseil crash symbolizer)
//   * runtime/src/main.cpp                 (FormatHostStackTrace crash dump)
//   * runtime/src/memory.cpp               (invalid-guest-access stack dump)
//   * dawn tint utils/command/command_windows.cc (ImageNtHeader probe; it only
//     needs the DECLARATION — it loads Dbghelp.dll dynamically and tolerates
//     its absence)
//
// This stub supplies those exact symbols as *header-only inline no-ops* so the
// code compiles and links without importing the desktop-only dbghelp.dll /
// dbghelp.lib (which the UWP partition does not export). Struct layouts match
// SDK 10.0.28000.0 um\dbghelp.h field-for-field (pack 8) so any TU that does
// `sizeof(SYMBOL_INFO) + MAX_SYM_NAME` buffering behaves exactly as it does on
// the native Clang build.
//
// Semantics: no symbol database exists on UWP/Xbox (the product's own
// TranslatedFunctionRegistry already falls back for translated frames), so
// SymInitialize "succeeds" but SymFromAddr/SymGetLineFromAddr64 report "no
// symbol" — the crash dump degrades to module+offset, which is acceptable.
//
// Guarded on the UWP Store partition AND MSVC so it can never shadow the real
// dbghelp.h on the native (Clang/llvm-mingw) build, which has its own complete
// header tree and real DbgHelp linkage. The toolchain places this directory
// FIRST on the include path, so under UWP this stub is found before any real
// dbghelp.h (the partial SDK's um copy is unreachable anyway under the
// partition macros).
#pragma once

#if defined(_MSC_VER) && defined(WINAPI_FAMILY) && WINAPI_FAMILY == WINAPI_FAMILY_APP

#include <windows.h>
#include <winbase.h>
#include <winnt.h>
#include <pshpack8.h>

// Layout constants — identical to um\dbghelp.h (DESKTOP|GAMES region).
#define MAX_SYM_NAME 2000

#ifdef _WIN64
#ifndef _IMAGEHLP64
#define _IMAGEHLP64
#endif
#endif

// Sym option flags (SymSetOptions/SymGetOptions). Values match um\dbghelp.h.
#define SYMOPT_CASE_INSENSITIVE          0x00000001
#define SYMOPT_UNDNAME                   0x00000002
#define SYMOPT_DEFERRED_LOADS            0x00000004
#define SYMOPT_NO_CPP                    0x00000008
#define SYMOPT_LOAD_LINES                0x00000010
#define SYMOPT_OMAP_FIND_NEAREST         0x00000020
#define SYMOPT_LOAD_ANYTHING             0x00000040
#define SYMOPT_IGNORE_CVREC              0x00000080
#define SYMOPT_NO_UNQUALIFIED_LOADS      0x00000100
#define SYMOPT_FAIL_CRITICAL_ERRORS      0x00000200
#define SYMOPT_EXACT_SYMBOLS             0x00000400
#define SYMOPT_ALLOW_ABSOLUTE_SYMBOLS    0x00000800
#define SYMOPT_IGNORE_NT_SYMPATH         0x00001000
#define SYMOPT_INCLUDE_32BIT_MODULES     0x00002000
#define SYMOPT_PUBLICS_ONLY              0x00004000
#define SYMOPT_NO_PUBLICS                0x00008000
#define SYMOPT_AUTO_PUBLICS              0x00100000
#define SYMOPT_NO_IMAGE_SEARCH           0x00200000
#define SYMOPT_SECURE                    0x00400000
#define SYMOPT_NO_PROMPTS                0x00800000
#define SYMOPT_OVERWRITE                 0x01000000
#define SYMOPT_IGNORE_IMAGEDIR           0x02000000
#define SYMOPT_FLAT_DIRECTORY            0x04000000
#define SYMOPT_FAVOR_COMPRESSED          0x08000000
#define SYMOPT_ALLOW_ZERO_ADDRESS        0x10000000
#define SYMOPT_DISABLE_SYMSRV_AUTODETECT 0x20000000
#define SYMOPT_READONLY_CACHE            0x40000000
#define SYMOPT_SYMPATH_LAST              0x80000000
#define SYMOPT_DISABLE_FAST_SYMBOLS      0x10000000

// Layout: um\dbghelp.h _SYMBOL_INFO (DESKTOP|GAMES region, pack 8).
typedef struct _SYMBOL_INFO {
    ULONG   SizeOfStruct;
    ULONG   TypeIndex;        // Type Index of symbol
    ULONG64 Reserved[2];
    ULONG   Index;
    ULONG   Size;
    ULONG64 ModBase;          // Base Address of module containing this symbol
    ULONG   Flags;
    ULONG64 Value;            // Value of symbol, ValuePresent should be 1
    ULONG64 Address;          // Address of symbol including base address of module
    ULONG   Register;         // register holding value or pointer to value
    ULONG   Scope;            // scope of the symbol
    ULONG   Tag;              // pdb classification
    ULONG   NameLen;          // Actual length of name
    ULONG   MaxNameLen;
    CHAR    Name[1];          // Name of symbol
} SYMBOL_INFO, *PSYMBOL_INFO;

// Layout: um\dbghelp.h _IMAGEHLP_SYMBOL64 (DESKTOP|GAMES region, pack 8).
typedef struct _IMAGEHLP_SYMBOL64 {
    DWORD   SizeOfStruct;     // set to sizeof(IMAGEHLP_SYMBOL64)
    DWORD64 Address;          // virtual address including dll base address
    DWORD   Size;             // estimated size of symbol, can be zero
    DWORD   Flags;            // info about the symbols, see the SYMF defines
    DWORD   MaxNameLength;    // maximum size of symbol name in 'Name'
    CHAR    Name[1];          // symbol name (null terminated string)
} IMAGEHLP_SYMBOL64, *PIMAGEHLP_SYMBOL64;

// Layout: um\dbghelp.h _IMAGEHLP_LINE64 (DESKTOP|GAMES region, pack 8).
typedef struct _IMAGEHLP_LINE64 {
    DWORD   SizeOfStruct;     // set to sizeof(IMAGEHLP_LINE64)
    PVOID   Key;              // internal
    DWORD   LineNumber;       // line number in file
    PCHAR   FileName;         // full filename
    DWORD64 Address;          // first instruction of line
} IMAGEHLP_LINE64, *PIMAGEHLP_LINE64;

#ifdef _IMAGEHLP64
#define IMAGEHLP_SYMBOL         IMAGEHLP_SYMBOL64
#define PIMAGEHLP_SYMBOL        PIMAGEHLP_SYMBOL64
#define IMAGEHLP_LINE           IMAGEHLP_LINE64
#define PIMAGEHLP_LINE          PIMAGEHLP_LINE64
#endif

#pragma poppack()

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__cplusplus)
#define MKW_DBGHELP_STUB_INLINE static inline
#else
#define MKW_DBGHELP_STUB_INLINE static __inline
#endif

// No symbol store on UWP: the session is "open" but empty, so callers keep
// their crash-dump flow (module+offset + TranslatedFunctionRegistry fallback)
// without tripping SymInitialize-failure paths (abseil treats that as FATAL).
MKW_DBGHELP_STUB_INLINE ULONG SymGetOptions(void) { return 0; }
MKW_DBGHELP_STUB_INLINE ULONG SymSetOptions(ULONG Options) { (void)Options; return 0; }
MKW_DBGHELP_STUB_INLINE BOOL SymInitialize(HANDLE Process, PCSTR UserSearchPath, BOOL fInvadeProcess)
{
    (void)Process; (void)UserSearchPath; (void)fInvadeProcess;
    return TRUE;
}
MKW_DBGHELP_STUB_INLINE BOOL SymCleanup(HANDLE Process) { (void)Process; return TRUE; }
MKW_DBGHELP_STUB_INLINE BOOL SymFromAddr(HANDLE Process, DWORD64 Address, PDWORD64 Displacement,
                                         PSYMBOL_INFO Symbol)
{
    (void)Process; (void)Address; (void)Displacement; (void)Symbol;
    return FALSE;  // no symbolization on UWP
}
MKW_DBGHELP_STUB_INLINE BOOL SymGetLineFromAddr64(HANDLE Process, DWORD64 qwAddr, PDWORD pdwDisplacement,
                                                  PIMAGEHLP_LINE64 Line64)
{
    (void)Process; (void)qwAddr; (void)pdwDisplacement; (void)Line64;
    return FALSE;  // no line info on UWP
}

// Declaration-only consumer (dawn tint command_windows.cc) resolves this
// dynamically at runtime and handles its absence; the inline no-op lets the
// `decltype(&ImageNtHeader)` type reference compile without a dbghelp.lib
// import. Returning nullptr == "not an executable image", matching what the
// caller already treats as the not-found case.
MKW_DBGHELP_STUB_INLINE PIMAGE_NT_HEADERS ImageNtHeader(PVOID Base)
{
    (void)Base;
    return nullptr;
}

#ifdef __cplusplus
}
#endif

#undef MKW_DBGHELP_STUB_INLINE

#endif  // _MSC_VER && WINAPI_FAMILY == WINAPI_FAMILY_APP
