# Frontend Visuals — Technical Reference

## Isometric Camera
- **Class:** `Camera3D` with custom `CameraController.gd`
- **Projection:** Orthogonal (no perspective distortion)
- **Lock Angles:** X: -30°, Y: 45°
- **Controls:** WASD panning, edge-panning (mouse at screen borders), mouse-wheel zoom (bounded by `min_zoom`/`max_zoom`)
- **Tracking:** Smooth `lerp` interpolation to follow `PlayerManager.current_avatar` on spacebar press

## Art Direction

### The Sinks (Low Class)
- **Geometry:** Modular, low-poly blocks. Haphazard construction, verticality restricted.
- **Lighting:** Dark, claustrophobic. Local point lights (flickering neon, barrel fires). Volumetric fog simulates smog.
- **Palette:** Grays, rusted browns, toxic greens, harsh neon pinks/blues.

### The Enclave (High Class)
- **Geometry:** Symmetrical, clean, brutalist architecture with floating structures.
- **Lighting:** Bright directional lighting (clear sunlight above smog layer). Soft shadows.
- **Palette:** Stark whites, gold trims, synthetic greens.

### The Countryside
- **Geometry:** Wide open spaces broken by massive industrial machinery.
- **Lighting:** Harsh, flat industrial lighting. High visibility makes stealth difficult.
- **Palette:** Dark metals, warning oranges, dust.

## Shader Notes
- **CRT Scanline Effect:** Applied to all terminal/NetFeed UI elements for retro-futuristic feel.
- **Volumetric Fog:** Sector-specific density controlled by `WorldDirector` (The Sinks = dense, The Enclave = clear).
- **Chromatic Aberration:** Subtle screen effect that intensifies with player stress/damage.
