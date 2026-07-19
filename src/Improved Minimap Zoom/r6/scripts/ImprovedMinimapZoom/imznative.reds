// Natives provided by the "Improved Minimap Zoom Native" RED4ext plugin
// (ImprovedMinimapZoom_Native.dll). The plugin is a REQUIRED dependency:
// without it these declarations fail script validation at game start.
//
// IMZ_GetMinimapRadius returns the minimap vision radius currently displayed
// on screen (the engine's interpolated value, not the target), read from
// native memory that 1.63 does not expose through RTTI. Returns -1.0 when the
// value cannot be read — treat any result <= 0 as unavailable.
//
// The plugin also registers a research-only native, IMZ_DumpMinimapMemory,
// which is intentionally NOT declared here: it stays inert unless research
// wiring is added (see native/RESEARCH.md for the recipe).
public static native func IMZ_GetMinimapRadius(ctrl: ref<IScriptable>) -> Float
