// MinimapDump.cpp
// IMZ_DumpMinimapMemory(ctrl: ref<IScriptable>, expectedZoom: Float, tag: String) -> Void
//
// Read-only research instrumentation. On first call it writes imz_props.txt
// (RTTI class chain: sizes + every reflected property offset — the six
// visionRadius* floats are the landmarks). On every call it appends one CSV
// row to imz_mem.csv with the instance's memory reinterpreted as floats at
// every 4-byte offset. Both files land next to this DLL.
//
// Analysis idea: while driving with dynamic zoom on, all six buckets are
// flattened to the expected zoom, so any OTHER column that tracks expectedZoom
// (smoothly, with lag) is the engine's live/target radius.
//
// NOTE: this probe native is DELIBERATELY kept in shipping builds. It is
// inert in normal play: the released mod scripts neither declare nor call it,
// and it creates its output files only when explicitly called. Keeping it in
// means future offset research (see RESEARCH.md) needs only the TEMP
// redscript wiring — no special dll build. Remove its registration in
// RegisterFunctions() if a probe-free dll is ever wanted.

#include "MinimapDump.h"
#include "Log.h"

// The 1.63-era SDK uses std::bit_cast without including <bit>; include it first.
#include <bit>

#include <RED4ext/RED4ext.hpp>

#include <Windows.h>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <vector>

namespace
{
    constexpr uint32_t kMaxDumpBytes = 0x1000;

    constexpr const char* kMinimapClassName = "gameuiMinimapContainerController";

    // Offset of the live (displayed, interpolated) vision radius inside
    // gameuiMinimapContainerController for game 1.63 Hotfix 1. Located via the
    // memory probe (IMZ_DumpMinimapMemory): it trails the visionRadius* bucket
    // writes mid-lerp while driving, and at peek press/release it still holds
    // the on-screen value after the buckets already hold the new target. It
    // sits in the unreflected native gap (0x280..0x35F) just before the six
    // reflected visionRadius* floats at 0x360..0x374. The game version is
    // frozen, so this offset never changes.
    // Full offset table, evidence, and the repeatable probe recipe: RESEARCH.md
    // in the project root.
    constexpr uint32_t kCurrentRadiusOffset = 0x338;

    std::mutex g_mutex;
    bool g_initialized = false;
    uint32_t g_dumpBytes = 0;
    std::ofstream g_csv;

    std::filesystem::path GetThisModuleDirectory()
    {
        HMODULE hModule = nullptr;
        if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               reinterpret_cast<LPCSTR>(&GetThisModuleDirectory), &hModule))
        {
            char path[MAX_PATH] = {0};
            if (GetModuleFileNameA(hModule, path, MAX_PATH) > 0)
            {
                return std::filesystem::path(path).parent_path();
            }
        }
        return std::filesystem::current_path();
    }

    const char* SafeCName(const RED4ext::CName& aName)
    {
        auto str = aName.ToString();
        return str ? str : "<unnamed>";
    }

    void WriteProps(std::ofstream& aOut, const char* aLabel, const RED4ext::DynArray<RED4ext::CProperty*>& aProps)
    {
        aOut << "  " << aLabel << " (" << aProps.size << "):\n";
        for (auto prop : aProps)
        {
            if (!prop)
                continue;
            char line[512];
            std::snprintf(line, sizeof(line), "    0x%04X  %-40s %s\n", prop->valueOffset, SafeCName(prop->name),
                          prop->type ? SafeCName(prop->type->GetName()) : "<untyped>");
            aOut << line;
        }
    }

    // Writes the class chain layout (sizes + reflected property offsets).
    void WritePropsFile(RED4ext::CClass* aCls, const std::filesystem::path& aDir)
    {
        std::ofstream f(aDir / "imz_props.txt", std::ios::trunc);
        if (!f)
        {
            Log::Warn("IMZ_DumpMinimapMemory: cannot open imz_props.txt for writing");
            return;
        }

        for (auto cls = aCls; cls; cls = cls->parent)
        {
            f << "class " << SafeCName(cls->name) << "  size=" << cls->size << " (0x" << std::hex << cls->size
              << std::dec << ")  holderSize=" << cls->holderSize << "\n";
            WriteProps(f, "props", cls->props);
            WriteProps(f, "nativeProps", cls->unk118);
            f << "\n";
        }
    }
}

// Native thunk. Signature per RED4ext scripting convention.
static void IMZ_DumpMinimapMemory(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    RED4ext::Handle<RED4ext::IScriptable> ctrl;
    float expectedZoom = 0.0f;
    RED4ext::CString tag;

    RED4ext::GetParameter(aFrame, &ctrl);
    RED4ext::GetParameter(aFrame, &expectedZoom);
    RED4ext::GetParameter(aFrame, &tag);
    aFrame->code++; // skip ParamEnd

    if (!ctrl)
    {
        Log::Warn("IMZ_DumpMinimapMemory: null controller handle; skipping");
        return;
    }

    std::lock_guard<std::mutex> lock(g_mutex);

    auto instance = reinterpret_cast<const uint8_t*>(ctrl.GetPtr());

    if (!g_initialized)
    {
        auto dir = GetThisModuleDirectory();

        // Use the instance's ACTUAL runtime class (could be a derived type).
        auto cls = ctrl->GetType();
        if (!cls)
        {
            Log::Error("IMZ_DumpMinimapMemory: instance has no RTTI class");
            return;
        }

        Log::Info("IMZ_DumpMinimapMemory: first call, class=%s size=%u", SafeCName(cls->name), cls->size);
        WritePropsFile(cls, dir);

        g_dumpBytes = cls->size < kMaxDumpBytes ? cls->size : kMaxDumpBytes;
        g_dumpBytes &= ~3u; // whole 4-byte words only

        g_csv.open(dir / "imz_mem.csv", std::ios::trunc);
        if (!g_csv)
        {
            Log::Error("IMZ_DumpMinimapMemory: cannot open imz_mem.csv for writing");
            return;
        }

        g_csv << "tick_ms,tag,expected";
        for (uint32_t off = 0; off < g_dumpBytes; off += 4)
        {
            char col[16];
            std::snprintf(col, sizeof(col), ",0x%04X", off);
            g_csv << col;
        }
        g_csv << "\n";

        g_initialized = true;
    }

    if (!g_csv)
        return;

    // Snapshot the instance memory first, then format from the copy.
    std::vector<uint8_t> buf(g_dumpBytes);
    std::memcpy(buf.data(), instance, g_dumpBytes);

    char head[128];
    std::snprintf(head, sizeof(head), "%llu,%s,%.3f", static_cast<unsigned long long>(GetTickCount64()),
                  tag.c_str() ? tag.c_str() : "", expectedZoom);
    g_csv << head;

    for (uint32_t off = 0; off < g_dumpBytes; off += 4)
    {
        float v;
        std::memcpy(&v, buf.data() + off, sizeof(v));

        char cell[32];
        if (std::isfinite(v))
            std::snprintf(cell, sizeof(cell), ",%.6g", v);
        else
            std::snprintf(cell, sizeof(cell), ",NA");
        g_csv << cell;
    }
    g_csv << "\n";
    g_csv.flush();
}

// IMZ_GetMinimapRadius(ctrl: ref<IScriptable>) -> Float
// Returns the currently displayed minimap vision radius, or -1.0 when it
// cannot be read (null handle, wrong class, implausible value) — script side
// treats <= 0 as "unavailable" and falls back to its config-based guess.
static void IMZ_GetMinimapRadius(RED4ext::IScriptable* aContext, RED4ext::CStackFrame* aFrame, void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(a4);

    RED4ext::Handle<RED4ext::IScriptable> ctrl;
    RED4ext::GetParameter(aFrame, &ctrl);
    aFrame->code++; // skip ParamEnd

    float result = -1.0f;

    if (ctrl)
    {
        auto rtti = RED4ext::CRTTISystem::Get();
        auto minimapCls = rtti ? rtti->GetClass(kMinimapClassName) : nullptr;
        auto cls = ctrl->GetType();
        if (cls && minimapCls && cls->IsA(minimapCls) && minimapCls->size >= kCurrentRadiusOffset + sizeof(float))
        {
            float v;
            std::memcpy(&v, reinterpret_cast<const uint8_t*>(ctrl.GetPtr()) + kCurrentRadiusOffset, sizeof(v));
            if (std::isfinite(v) && v > 1.0f && v < 1000.0f)
            {
                result = v;
            }
        }
    }

    if (aOut)
    {
        *reinterpret_cast<float*>(aOut) = result;
    }
}

void IMZNative::RegisterFunctions()
{
    auto rtti = RED4ext::CRTTISystem::Get();
    if (!rtti)
    {
        Log::Error("RegisterFunctions: RTTI system unavailable");
        return;
    }

    RED4ext::CBaseFunction::Flags flags = {.isNative = true, .isStatic = true};

    auto func = RED4ext::CGlobalFunction::Create("IMZ_DumpMinimapMemory", "IMZ_DumpMinimapMemory",
                                                 &IMZ_DumpMinimapMemory);
    func->flags = flags;
    func->AddParam("handle:IScriptable", "ctrl");
    func->AddParam("Float", "expectedZoom");
    func->AddParam("String", "tag");
    rtti->RegisterFunction(func);

    auto radiusFunc = RED4ext::CGlobalFunction::Create("IMZ_GetMinimapRadius", "IMZ_GetMinimapRadius",
                                                       &IMZ_GetMinimapRadius);
    radiusFunc->flags = flags;
    radiusFunc->AddParam("handle:IScriptable", "ctrl");
    radiusFunc->SetReturnType("Float");
    rtti->RegisterFunction(radiusFunc);

    Log::Info("Registered natives: IMZ_DumpMinimapMemory, IMZ_GetMinimapRadius");
}
