// Log.h
#pragma once
#include <string>
#include <cstdarg>

// Enable debug output by defining LOG_DEBUG to 1 in one translation unit (or via build flags).
#ifndef LOG_DEBUG
#define LOG_DEBUG 1
#endif

namespace Log
{
    // Narrow (char) APIs
    //
    // NOTE: narrow APIs accept UTF-8 encoded strings. They will be converted to UTF-16
    // and forwarded to the wide (UTF-16) implementations before emitting to the OS.
    // This preserves Unicode fidelity on Windows and avoids ambiguous ANSI conversions.
    void Info(const char* fmt, ...);
    void Debug(const char* fmt, ...);      // compiled out when LOG_DEBUG == 0
    void DebugWarn(const char* fmt, ...);
    void DebugError(const char* fmt, ...);

    // True severity levels (always emitted)
    void Warn(const char* fmt, ...);       // prints "[WARN] ..."
    void Error(const char* fmt, ...);      // prints "[ERROR] ..."

    // Wide (wchar_t) APIs for direct UTF-16 logging (core emitters)
    // These are the canonical emitters that call OutputDebugStringW.
    void InfoW(const wchar_t* fmt, ...);
    void DebugW(const wchar_t* fmt, ...);
    void DebugWarnW(const wchar_t* fmt, ...);
    void DebugErrorW(const wchar_t* fmt, ...);

    // Wide true severity levels (always emitted)
    void WarnW(const wchar_t* fmt, ...);
    void ErrorW(const wchar_t* fmt, ...);
}
