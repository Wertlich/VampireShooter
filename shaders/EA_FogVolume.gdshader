shader_type fog;
// Ground mist for the demo cemetery. This is real volumetric fog: the engine marches through
// the volume and shades it in 3D, so the mist has no surfaces of its own - no cards, no
// sprites, nothing that can turn edge-on to the camera and show up as a flat disc.
// Density comes from two octaves of 3D value noise that slide through the volume over time,
// which is what makes the mist creep instead of sitting still.

// overall thickness of the mist inside this volume
uniform float base_density : hint_range(0.0, 1.0) = 0.055;
// size of one noise cell in metres: larger = broader, slower banks of mist
uniform float cell_size : hint_range(1.0, 60.0) = 14.0;
// metres per second the mist drifts through the volume
uniform vec3 drift = vec3(0.35, 0.02, 0.22);
// share of the volume height the mist fills, measured from its floor
uniform float fill_height : hint_range(0.05, 1.0) = 0.6;
// how much of the box is spent fading out at its sides, so the volume has no visible walls
uniform float edge_fade : hint_range(0.0, 0.5) = 0.28;
// lower values leave more open gaps between the banks
uniform float coverage : hint_range(0.0, 1.0) = 0.45;
uniform vec3 fog_albedo : source_color = vec3(0.63, 0.75, 0.85);
uniform vec3 fog_emission : source_color = vec3(0.05, 0.11, 0.16);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z);
}

void fog() {
	vec3 p = WORLD_POSITION / max(cell_size, 0.001) + drift * TIME / max(cell_size, 0.001);
	// two octaves: the broad banks, and a finer curl that keeps their edges from looking drawn
	float n = vnoise(p) * 0.68 + vnoise(p * 2.6 + 17.3) * 0.32;
	n = smoothstep(1.0 - coverage, 1.0, n);

	// thickest along the floor of the volume, gone by fill_height
	float h = 1.0 - smoothstep(0.0, max(fill_height, 0.001), UVW.y);
	// and gone again before the sides of the box, so its walls never show as a straight line
	vec3 d = abs(UVW - 0.5) * 2.0;
	float sides = 1.0 - smoothstep(1.0 - edge_fade * 2.0, 1.0, max(d.x, d.z));

	DENSITY = base_density * n * h * sides;
	ALBEDO = fog_albedo;
	EMISSION = fog_emission;
}
