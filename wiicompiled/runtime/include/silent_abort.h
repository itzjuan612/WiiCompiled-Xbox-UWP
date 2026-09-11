#pragma once

#ifndef MKW_SILENT_ABORT_H
#define MKW_SILENT_ABORT_H

#include <cstdio>
#include <cstdlib>

// Site marker for abort() calls that bypass ShowRuntimeFatalPopup. The SIGABRT
// fatal handler copies this into crash_sigabrt.txt so an on-device repro can be
// attributed to an exact source site without a debugger attached.
extern const char* g_mkwSilentAbortSite;

#define MKW_SILENT_ABORT(site)                                                          \
    do {                                                                                \
        g_mkwSilentAbortSite = (site);                                                  \
        std::fprintf(stderr, "[fatal-pre] silent abort site: %s\n", (site));            \
        std::fflush(stderr);                                                            \
        std::abort();                                                                   \
    } while (0)

#endif // MKW_SILENT_ABORT_H
