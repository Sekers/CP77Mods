// Main.cpp
// Improved Minimap Zoom Native — RED4ext plugin for the Improved Minimap Zoom
// mod (game 1.63 HF1). Registers the IMZ_GetMinimapRadius script native (live
// zoom readback) plus the inert IMZ_DumpMinimapMemory research probe (see
// MinimapDump.cpp). Lifecycle mirrors the Skip Intros and Breaching plugin
// (proven on 1.63). Deploys to red4ext/plugins/ImprovedMinimapZoom/.

#include "MinimapDump.h"
#include "Log.h"

// The 1.63-era SDK uses std::bit_cast without including <bit>; include it first.
#include <bit>

#include <RED4ext/RED4ext.hpp>

static void RegisterTypesImpl()
{
}

static void PostRegisterTypesImpl()
{
    IMZNative::RegisterFunctions();
    Log::Info("Runtime initialization complete.");
}

// Exported plugin functions
RED4EXT_C_EXPORT void RED4EXT_CALL RegisterTypes() { RegisterTypesImpl(); }
RED4EXT_C_EXPORT void RED4EXT_CALL PostRegisterTypes() { PostRegisterTypesImpl(); }

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(
    RED4ext::PluginHandle,
    RED4ext::EMainReason aReason,
    const RED4ext::Sdk*)
{
    if (aReason == RED4ext::EMainReason::Load)
    {
        RED4ext::RTTIRegistrator::Add(RegisterTypes, PostRegisterTypes);
    }

    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::PluginInfo* aInfo)
{
    aInfo->name    = L"ImprovedMinimapZoom_Native";
    aInfo->author  = L"Legacy2077";
    aInfo->version = RED4EXT_SEMVER(0,2,0);
    // Runtime-independent like RED4.RTTIDumper: the SDK checkout's
    // RED4EXT_RUNTIME_LATEST resolves to a post-1.63 patch, which makes
    // RED4ext 1.15.0 refuse to load the plugin on 1.63 Hotfix 1.
    aInfo->runtime = RED4EXT_RUNTIME_INDEPENDENT;
    aInfo->sdk     = RED4EXT_SDK_LATEST;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_LATEST;
}
