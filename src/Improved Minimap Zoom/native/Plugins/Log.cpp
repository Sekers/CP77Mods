// Log.cpp
#include "Log.h"
#include <Windows.h>
#include <string>
#include <vector>
#include <cstdio>
#include <memory>

namespace
{
    static constexpr const char* kPrefixA = "ImprovedMinimapZoomNative: ";
    static constexpr const wchar_t* kPrefixW = L"ImprovedMinimapZoomNative: ";

    // Helper to format narrow string using a va_list.
    // Uses va_copy twice: once to compute required size, once to actually format.
    std::string FormatA(const char* fmt, va_list args)
    {
        va_list tmp;
        va_copy(tmp, args);
        int needed = _vscprintf(fmt, tmp) + 1;
        va_end(tmp);

        std::string buf;
        if (needed <= 0)
            return buf;

        buf.resize(static_cast<size_t>(needed));

        va_list tmp2;
        va_copy(tmp2, args);
        vsnprintf_s(&buf[0], buf.size(), _TRUNCATE, fmt, tmp2);
        va_end(tmp2);

        if (!buf.empty() && buf.back() == '\0') buf.pop_back();
        return buf;
    }

    // Helper to format wide string using a va_list.
    // Uses va_copy twice: once to compute required size, once to actually format.
    std::wstring FormatW(const wchar_t* fmt, va_list args)
    {
        va_list tmp;
        va_copy(tmp, args);
        int needed = _vscwprintf(fmt, tmp) + 1;
        va_end(tmp);

        std::wstring buf;
        if (needed <= 0)
            return buf;

        buf.resize(static_cast<size_t>(needed));

        va_list tmp2;
        va_copy(tmp2, args);
        vswprintf_s(&buf[0], buf.size(), fmt, tmp2);
        va_end(tmp2);

        if (!buf.empty() && buf.back() == L'\0') buf.pop_back();
        return buf;
    }

    // Convert UTF-8 narrow string to UTF-16 wide string (returns empty on failure).
    static std::wstring Utf8ToWide(const std::string& s)
    {
        if (s.empty()) return std::wstring();
        int needed = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
        if (needed <= 0) return std::wstring();
        std::wstring out;
        out.resize(static_cast<size_t>(needed));
        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), &out[0], needed);
        return out;
    }

    void OutputA(const std::string& s) { OutputDebugStringA(s.c_str()); }
    void OutputW(const std::wstring& s) { OutputDebugStringW(s.c_str()); }
}

// Narrow implementations: convert UTF-8 to UTF-16 and forward to wide implementations.
void Log::Info(const char* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::string body = FormatA(fmt, args);
    va_end(args);

    std::wstring wbody = Utf8ToWide(body);
    if (!wbody.empty())
    {
        Log::InfoW(wbody.c_str());
    }
    else
    {
        // Fallback to ASCII narrow output if conversion fails.
        std::string out = std::string(kPrefixA) + "[INFO] " + body + "\n";
        OutputA(out);
    }
}

#if LOG_DEBUG
void Log::Debug(const char* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::string body = FormatA(fmt, args);
    va_end(args);

    std::wstring wbody = Utf8ToWide(body);
    if (!wbody.empty())
    {
        Log::DebugW(wbody.c_str());
    }
    else
    {
        std::string out = std::string(kPrefixA) + "[DEBUG] " + body + "\n";
        OutputA(out);
    }
}

void Log::DebugWarn(const char* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::string body = FormatA(fmt, args);
    va_end(args);

    std::wstring wbody = Utf8ToWide(body);
    if (!wbody.empty())
    {
        Log::DebugWarnW(wbody.c_str());
    }
    else
    {
        std::string out = std::string(kPrefixA) + "[DEBUG] WARNING: " + body + "\n";
        OutputA(out);
    }
}

void Log::DebugError(const char* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::string body = FormatA(fmt, args);
    va_end(args);

    std::wstring wbody = Utf8ToWide(body);
    if (!wbody.empty())
    {
        Log::DebugErrorW(wbody.c_str());
    }
    else
    {
        std::string out = std::string(kPrefixA) + "[DEBUG] ERROR: " + body + "\n";
        OutputA(out);
    }
}
#else
void Log::Debug(const char* fmt, ...) { (void)fmt; }
void Log::DebugWarn(const char* fmt, ...) { (void)fmt; }
void Log::DebugError(const char* fmt, ...) { (void)fmt; }
#endif

// Narrow true severity levels (always emitted)
void Log::Warn(const char* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::string body = FormatA(fmt, args);
    va_end(args);

    std::wstring wbody = Utf8ToWide(body);
    if (!wbody.empty())
    {
        Log::WarnW(wbody.c_str());
    }
    else
    {
        std::string out = std::string(kPrefixA) + "[WARN] " + body + "\n";
        OutputA(out);
    }
}

void Log::Error(const char* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::string body = FormatA(fmt, args);
    va_end(args);

    std::wstring wbody = Utf8ToWide(body);
    if (!wbody.empty())
    {
        Log::ErrorW(wbody.c_str());
    }
    else
    {
        std::string out = std::string(kPrefixA) + "[ERROR] " + body + "\n";
        OutputA(out);
    }
}

// Wide implementations (canonical emitters)
void Log::InfoW(const wchar_t* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::wstring body = FormatW(fmt, args);
    va_end(args);
    std::wstring out = std::wstring(kPrefixW) + L"[INFO] " + body + L"\n";
    OutputW(out);
}

#if LOG_DEBUG
void Log::DebugW(const wchar_t* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::wstring body = FormatW(fmt, args);
    va_end(args);
    std::wstring out = std::wstring(kPrefixW) + L"[DEBUG] " + body + L"\n";
    OutputW(out);
}

void Log::DebugWarnW(const wchar_t* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::wstring body = FormatW(fmt, args);
    va_end(args);
    std::wstring out = std::wstring(kPrefixW) + L"[DEBUG] WARNING: " + body + L"\n";
    OutputW(out);
}

void Log::DebugErrorW(const wchar_t* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::wstring body = FormatW(fmt, args);
    va_end(args);
    std::wstring out = std::wstring(kPrefixW) + L"[DEBUG] ERROR: " + body + L"\n";
    OutputW(out);
}
#else
void Log::DebugW(const wchar_t* fmt, ...) { (void)fmt; }
void Log::DebugWarnW(const wchar_t* fmt, ...) { (void)fmt; }
void Log::DebugErrorW(const wchar_t* fmt, ...) { (void)fmt; }
#endif

// Wide true severity levels (always emitted)
void Log::WarnW(const wchar_t* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::wstring body = FormatW(fmt, args);
    va_end(args);
    std::wstring out = std::wstring(kPrefixW) + L"[WARN] " + body + L"\n";
    OutputW(out);
}

void Log::ErrorW(const wchar_t* fmt, ...)
{
    va_list args; va_start(args, fmt);
    std::wstring body = FormatW(fmt, args);
    va_end(args);
    std::wstring out = std::wstring(kPrefixW) + L"[ERROR] " + body + L"\n";
    OutputW(out);
}
