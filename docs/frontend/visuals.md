# Frontend Systems: Visuals & Interface

## The Isometric Camera
The game uses a fixed 3D isometric perspective. 
- **Camera Configuration:** An Orthogonal Camera3D set to a specific angle (e.g., X: -30 degrees, Y: 45 degrees).
- **Controller:** The `CameraController` script will handle panning (using WASD or screen edge detection) and zooming, while maintaining the strict isometric angle. It will follow the player but allow the player to 'detach' and scout ahead.

## Art Style: Corporate Brutalism vs. High-Tech Slum
The visual language is designed to emphasize class division.

### The Sinks (Low Class)
- **Geometry:** Modular, low-poly blocks. Haphazard construction.
- **Lighting:** Dark, claustrophobic. Relies heavily on local point lights (flickering neon, barrel fires) rather than a global sun. Volumetric fog is used to simulate smog and limit draw distance.
- **Color Palette:** Grays, rusted browns, toxic greens, and harsh neon pinks/blues.

### The Enclave (High Class)
- **Geometry:** Symmetrical, clean, brutalist architecture mixed with impossible floating structures.
- **Lighting:** Bright, directional lighting (simulating clear sunlight above the smog layer). Soft shadows.
- **Color Palette:** Stark whites, gold trims, and lush, synthetic greens.

## UI Systems
- **Minimalist HUD:** To increase immersion, the UI should be diegetic where possible (e.g., ammo counters on the weapon model, health indicated by posture or screen effects).
- **Terminal Interfaces:** Hacking or reading lore occurs via fullscreen "terminal" overlays that look like retro-futuristic DOS interfaces.
