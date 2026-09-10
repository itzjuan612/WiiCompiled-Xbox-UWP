#pragma once
// UWP build prelude (force-included into every Dawn/Tint TU via -include).
//
// Purpose 1 - consistent Windows header environment:
//   Several Dawn D3D TUs include only a narrow header (e.g. <winerror.h> in
//   D3DError.h) and use HRESULT / COM interfaces (IErrorInfo in comdef.h) that
//   are only reachable through the full <windows.h> under the UWP
//   (WINAPI_FAMILY_APP) header chain. On the desktop chain those narrow
//   includes happen to pull in windef.h; on UWP they do not. Force-including
//   <windows.h> guarantees HRESULT and the COM interfaces are always defined.
//
// Purpose 2 - do NOT leak the COM macros into C++:
//   rpcndr.h / wtypes.h (pulled in by windows.h) define IN / OUT / OPTIONAL /
//   INOUT as empty macros. Tint uses IN as a C++ template parameter name
//   (std::vector<IN>), so those macros must be undefined. This mirrors what
//   Dawn's own src/utils/windows_with_undefs.h does for CreateWindow,
//   GetMessage, MemoryBarrier, GetCurrentTime (which are also undefined below).
#include <windows.h>

#undef IN
#undef OUT
#undef INOUT
#undef INOUTREF
#undef OPTIONAL
#undef IN_RANGE
#undef OUT_RANGE
#undef CREATEGUID

#undef CreateWindow
#undef GetMessage
#undef MemoryBarrier
#undef GetCurrentTime
