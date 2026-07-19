// MinimapDump.h
// Phase A research native: dump the minimap controller's instance memory so we
// can locate the live (interpolated) vision radius, which 1.63 RTTI does not
// expose to scripts.
#pragma once

namespace IMZNative
{
    // Registers the script-callable global native functions.
    // Call from PostRegisterTypes.
    void RegisterFunctions();
}
