// EmacEArt Stylized Skybox - a stylized procedural sky for Godot 4.
//
// One shader draws the whole sky: zenith/horizon/ground gradient, azimuthal (compass)
// sky gradient, aerial-perspective haze, sun disc + glow corona,
// procedural clouds with five pattern styles and posterization, and finally a
// small color grading chain (exposure, contrast, saturation, lift/gamma/gain).
//
// The shader also feeds Godot ambient light and reflections: with the Environment set to
// use the sky for ambient and reflected light, the whole scene picks up the sky colors.
//
// Copyright (c) 2026 EmacEArt (Maciej). EmacEArt Asset License - use it in your own
// projects, personal and commercial; do not sell or redistribute the asset itself.
// Full text: LICENSE.txt in the project root.

shader_type sky;

group_uniforms Zenith_and_Horizon;
uniform vec4 zenith_color : source_color = vec4(0.05, 0.08, 0.22, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.38, 0.55, 0.82, 1.0);
uniform vec4 ground_color : source_color = vec4(0.12, 0.10, 0.08, 1.0);
uniform float horizon_sharpness : hint_range(0.5, 16.0) = 4.0;
// Shifts the sky gradient only. The ground hemisphere stays at the real horizon so it
// cannot bleed into the upper sky at extreme values.
uniform float horizon_offset : hint_range(-0.5, 0.5) = 0.0;

group_uniforms Sun;
// ON  - the sun sits where the DirectionalLight3D points from (its Sky Mode must include
//       the sky). Sky, shadows and lighting stay in sync by themselves.
// OFF - the sun sits where sun_direction_manual points, independent of any light.
uniform bool sun_follows_light = true;
uniform vec3 sun_direction_manual = vec3(0.3, 0.6, 0.5);
uniform vec4 sun_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 sun_glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float sun_size : hint_range(0.0005, 0.05) = 0.003;
uniform float sun_glow_size : hint_range(0.01, 1.0) = 0.132;
uniform float sun_glow_falloff : hint_range(1.0, 16.0) = 16.0;

group_uniforms Sky_Gradient;
uniform vec4 sky_gradient_color : source_color = vec4(1.0, 0.45, 0.10, 1.0);
uniform float sky_gradient_angle : hint_range(0.0, 360.0) = 0.0;
uniform float sky_gradient_spread : hint_range(0.01, 1.0) = 0.5;
uniform float sky_gradient_strength : hint_range(0.0, 1.0) = 0.0;

group_uniforms Atmosphere;
uniform vec4 atmosphere_color : source_color = vec4(0.20, 0.35, 0.60, 1.0);
uniform float atmosphere_strength : hint_range(0.0, 1.5) = 0.55;
uniform float atmosphere_falloff : hint_range(1.0, 10.0) = 2.5;

group_uniforms Color_Grading;
uniform float exposure : hint_range(0.1, 4.0) = 1.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.05;
uniform float saturation : hint_range(0.0, 2.5) = 1.1;
uniform vec4 lift : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 gamma_midtones : source_color = vec4(0.5, 0.5, 0.5, 0.0);
uniform vec4 gain : source_color = vec4(1.0, 1.0, 1.0, 0.0);

group_uniforms Clouds;
uniform bool clouds_enabled = false;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.72, 0.78, 0.88, 1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_softness : hint_range(0.001, 0.5) = 0.15;
uniform float cloud_bands : hint_range(1.0, 8.0) = 1.0;
uniform float cloud_density : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_stretch : hint_range(0.0, 0.97) = 0.3;
uniform float cloud_swirl : hint_range(0.0, 1.0) = 0.0;
// 0 = Standard, 1 = Feathered, 2 = Round, 3 = Diagonal, 4 = Cubic
uniform float cloud_style : hint_range(0.0, 4.0) = 0.0;
uniform float cloud_scale : hint_range(0.5, 8.0) = 3.0;
uniform float cloud_height : hint_range(0.0, 0.5) = 0.05;
uniform float cloud_speed : hint_range(0.0, 1.0) = 0.03;

// Godot hands color uniforms to the shader already converted from sRGB to linear, so mid
// grey in the picker arrives as 0.2140. Dividing by that makes mid grey the neutral point
// of the gamma control.
const float GAMMA_NEUTRAL = 1.0 / 0.21404114;


// -- Helpers -------------------------------------------------------------------
vec3 apply_contrast(vec3 col, float amount) {
	// Clamp: dark colors + high contrast would produce sub-zero values -> pure black
	return max((col - 0.5) * amount + 0.5, vec3(0.0));
}

vec3 apply_saturation(vec3 col, float amount) {
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	// Clamp: amount > 1 on near-black channels produces sub-zero values
	return max(mix(vec3(lum), col, amount), vec3(0.0));
}

// ASC CDL: lift/gamma/gain per channel
vec3 apply_lift_gamma_gain(vec3 col, vec3 l, vec3 g, vec3 gn) {
	col = col * gn + l;
	return sign(col) * pow(abs(col), 1.0 / max(g, vec3(0.001)));
}


// -- Cloud noise (simplex + 4-octave FBM) --------------------------------------
// Simplex noise, not value noise. Value noise sits on a square lattice: its slope breaks
// along the cell borders, and once the pattern is stretched or posterized those borders
// show up as straight, axis-aligned edges - rectangular patches in the sky. Simplex uses
// a triangular lattice with continuous gradients, so there is no axis-aligned structure
// to become visible at any stretch setting.
float cloud_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 sx_mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 sx_mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 sx_permute(vec3 x) { return sx_mod289(((x * 34.0) + 1.0) * x); }

// Returns roughly -1..1
float cloud_simplex(vec2 v) {
	const vec4 C = vec4(0.211324865405187, 0.366025403784439,
			-0.577350269189626, 0.024390243902439);
	vec2 i  = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;
	i = sx_mod289(i);
	vec3 p = sx_permute(sx_permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;
	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x  = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

// 0..1 wrapper. The 0.35 factor keeps the visible cloud size the same as before the
// noise was swapped - simplex cells are smaller than square-lattice cells at the same
// coordinate scale, so without it every material would suddenly look finer grained.
float cloud_noise(vec2 p) {
	return clamp(cloud_simplex(p * 0.35) * 0.5 + 0.5, 0.0, 1.0);
}

// Each octave is rotated by a fraction of a turn, so repeated octaves cannot line up
// into a visible grid.
const mat2 CLOUD_OCTAVE_ROT = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));

float cloud_fbm(vec2 p) {
	vec2 q = p;
	float v = cloud_noise(q) * 0.5000;
	q = CLOUD_OCTAVE_ROT * q * 2.1 + vec2(5.2, 1.3);
	v += cloud_noise(q) * 0.2500;
	q = CLOUD_OCTAVE_ROT * q * 2.05 + vec2(9.7, 2.8);
	v += cloud_noise(q) * 0.1250;
	q = CLOUD_OCTAVE_ROT * q * 2.02 + vec2(3.1, 7.4);
	v += cloud_noise(q) * 0.0625;
	return v * (1.0 / 0.9375);
}

// Style 1: Feathered - ridged FBM. Inverts the noise around 0.5, so thin ridges appear
// where the noise crosses 0.5 - the cirrus look.
float cloud_fbm_ridged(vec2 p) {
	vec2 q = p;
	float v = (1.0 - abs(cloud_noise(q) * 2.0 - 1.0)) * 0.5000;
	q = CLOUD_OCTAVE_ROT * q * 2.1 + vec2(5.2, 1.3);
	v += (1.0 - abs(cloud_noise(q) * 2.0 - 1.0)) * 0.2500;
	q = CLOUD_OCTAVE_ROT * q * 2.05 + vec2(9.7, 2.8);
	v += (1.0 - abs(cloud_noise(q) * 2.0 - 1.0)) * 0.1250;
	q = CLOUD_OCTAVE_ROT * q * 2.02 + vec2(3.1, 7.4);
	v += (1.0 - abs(cloud_noise(q) * 2.0 - 1.0)) * 0.0625;
	return clamp(v * (1.0 / 0.9375), 0.0, 1.0);
}

// Style 2: Voronoi - round, separated cells
vec2 voronoi_center(vec2 cell) {
	return cell + vec2(cloud_hash(cell), cloud_hash(cell + vec2(5.3, 2.1)));
}

float cloud_voronoi_euclid(vec2 p) {
	vec2 i = floor(p);
	float min_d = 10.0;
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			vec2 c = voronoi_center(i + vec2(float(dx), float(dy)));
			min_d = min(min_d, length(p - c));
		}
	}
	return 1.0 - clamp(min_d * 1.35, 0.0, 1.0);
}

// Style 4: Cotton - the same cell centres as style 2, but joined with a smooth minimum
// instead of a plain minimum. The cell walls disappear and neighbouring cells grow into
// one connected, lobed mass, the way heaped cumulus piles up. A slow noise pushes the
// falloff in and out so the lobes never come out as clean circles - that is what keeps
// this apart from style 2, where every blob stands on its own with a seam around it.
float cloud_cotton(vec2 p) {
	vec2 i = floor(p);
	const float K = 5.5;   // higher = cells stay separate, lower = everything melts
	float acc = 0.0;
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			vec2 c = voronoi_center(i + vec2(float(dx), float(dy)));
			acc += exp(-K * length(p - c));
		}
	}
	// Exponential smooth minimum of the cell distances
	float d_smooth = -log(max(acc, 1e-5)) / K;
	// Break the circles: the edge of the mass wanders with a low-frequency noise
	d_smooth -= (cloud_noise(p * 1.6) - 0.5) * 0.42;
	d_smooth -= (cloud_noise(p * 3.7 + vec2(6.1, 2.4)) - 0.5) * 0.18;
	return 1.0 - clamp(d_smooth * 1.55, 0.0, 1.0);
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y + horizon_offset;

	// -- Sky gradient ------------------------------------------------------
	float sky_t = clamp(pow(clamp(up, 0.0, 1.0), 1.0 / horizon_sharpness), 0.0, 1.0);

	// The ground uses raw dir.y - the offset shifts the sky gradient only, not the
	// physical hemisphere boundary.
	float ground_t = clamp(pow(clamp(-dir.y, 0.0, 1.0), 2.0), 0.0, 1.0);

	vec3 sky_col = mix(horizon_color.rgb, zenith_color.rgb, sky_t);
	sky_col = mix(sky_col, ground_color.rgb, ground_t);

	// -- Azimuthal sky gradient (side-to-side compass tint) ----------------
	{
		float ang = sky_gradient_angle * 0.01745329252; // degrees to radians
		vec2 grad_h = vec2(sin(ang), cos(ang));         // compass direction vector
		vec2 dir_h = vec2(dir.x, dir.z);
		float d_len = length(dir_h);
		float az_dot = d_len > 0.001 ? dot(dir_h / d_len, grad_h) : 0.0; // -1..1
		// Linear ramp across the whole sky - always visible when strength > 0
		float t_az = clamp(az_dot * 0.5 + 0.5, 0.0, 1.0);
		// Spread controls falloff sharpness: 1 = soft full sky, 0.1 = hard half sphere
		t_az = pow(t_az, max(1.0 / sky_gradient_spread, 0.01));
		sky_col = mix(sky_col, sky_gradient_color.rgb,
				t_az * sky_gradient_strength * (1.0 - ground_t));
	}

	// -- Aerial perspective - atmospheric haze at the horizon --------------
	float horizon_factor = pow(clamp(1.0 - abs(up), 0.0, 1.0), atmosphere_falloff);
	sky_col += atmosphere_color.rgb * horizon_factor * atmosphere_strength * (1.0 - ground_t);

	// -- Sun ---------------------------------------------------------------
	vec3 sun_dir = normalize(sun_direction_manual);
	if (sun_follows_light && LIGHT0_ENABLED) {
		sun_dir = normalize(LIGHT0_DIRECTION);
	}
	float cos_a = dot(dir, sun_dir);

	// Hard disc
	float sun_disc = 1.0 - smoothstep(sun_size - 0.0002, sun_size + 0.0002, 1.0 - cos_a);

	// Glow corona (additive)
	float glow_t = clamp((cos_a - (1.0 - sun_glow_size)) / sun_glow_size, 0.0, 1.0);
	float sun_glow = pow(glow_t, sun_glow_falloff);

	sky_col += sun_glow_color.rgb * sun_glow * (1.0 - ground_t);
	sky_col = mix(sky_col, sun_color.rgb, sun_disc * (1.0 - ground_t));

	// -- Clouds ------------------------------------------------------------
	if (clouds_enabled) {
		// Fade in above the minimum elevation, disappear toward the ground
		float elev_mask = clamp((dir.y - cloud_height) / max(cloud_softness, 0.01), 0.0, 1.0)
				* (1.0 - ground_t);

		// Perspective projection onto a horizontal cloud plane + time scroll
		vec2 cloud_uv = (dir.xz / max(dir.y + 0.1, 0.1)) * cloud_scale;
		cloud_uv.x += TIME * cloud_speed;

		// -- Domain warp -----------------------------------------------
		if (cloud_stretch > 0.01 || cloud_swirl > 0.01) {
			// Stretch - non-linear (squared): slow start, dramatic at high values.
			// Most of the stretching is done by squashing the sampling coordinate, which
			// pulls the pattern into long horizontal streaks without folding the domain
			// back onto itself. Only a small displacement is left on top, to keep the
			// streaks from running perfectly parallel.
			float sa = cloud_stretch * cloud_stretch;
			cloud_uv.x /= 1.0 + sa * 4.0;
			float wx = cloud_noise(cloud_uv * 0.28);
			float wy = cloud_noise(cloud_uv * 0.28 + vec2(4.7, 2.1));
			cloud_uv.x += (wx - 0.5) * sa * 2.2;
			cloud_uv.y += (wy - 0.5) * sa * 0.6;

			// Swirl - second-level domain warp with a perpendicular component.
			// vec2(-d.y, d.x) = 90-degree rotation of d -> organic swirling.
			if (cloud_swirl > 0.01) {
				float sx = cloud_noise(cloud_uv * 0.32 + vec2(1.7, 9.2));
				float sy = cloud_noise(cloud_uv * 0.32 + vec2(8.3, 2.8));
				vec2 d = vec2(sx - 0.5, sy - 0.5);
				cloud_uv += d * cloud_swirl * 3.2               // linear component
						+ vec2(-d.y, d.x) * cloud_swirl * 2.4;  // perpendicular = rotation
			}
		}

		// -- Pattern style selector ------------------------------------
		int c_style = int(round(cloud_style));
		float n;
		if (c_style == 1) {
			n = cloud_fbm_ridged(cloud_uv);              // feathered / cirrus
		} else if (c_style == 2) {
			n = cloud_voronoi_euclid(cloud_uv);          // round blobs
		} else if (c_style == 3) {                       // diagonal 45 deg
			vec2 r_uv = vec2(cloud_uv.x * 0.7071 - cloud_uv.y * 0.7071,
					cloud_uv.x * 0.7071 + cloud_uv.y * 0.7071);
			n = cloud_fbm(r_uv);
		} else if (c_style == 4) {
			n = cloud_cotton(cloud_uv);                  // merged, lobed masses
		} else {
			n = cloud_fbm(cloud_uv);                     // standard
		}

		// -- Posterization: bands > 1 -> cel-shaded stepped look --------
		float bands = max(cloud_bands, 1.0);
		float n_q = bands > 1.5 ? ceil(n * bands) / bands : n;

		// How far this pixel is past the coverage threshold. Continuous in coverage, so
		// dragging the slider creeps the cloud edge outward instead of making it jump.
		float d = n - (1.0 - cloud_coverage);
		// The steps are put on THIS distance, not on the raw noise. Quantizing the noise
		// (the earlier version) tied the steps to fixed noise levels, so the coverage
		// slider did nothing until it crossed one and then a whole band appeared at once.
		// Quantizing the distance keeps the first step glued to the threshold: the pixel
		// just inside the cloud jumps straight to a full step, which is what gives the
		// hard cut-out edge, while the edge itself still moves smoothly with coverage.
		float d_q = bands > 1.5 ? ceil(d * bands) / bands : d;

		float t = clamp(d_q / max(cloud_softness, 0.005), 0.0, 1.0);
		float cloud_alpha = t * t * (3.0 - 2.0 * t) * elev_mask * cloud_density;

		// Color driven by band level: low band = shadow, high band = lit
		float band_level = clamp((n_q - (1.0 - cloud_coverage)) * bands, 0.0, 1.0);
		vec3 cloud_col = mix(cloud_shadow_color.rgb, cloud_color.rgb, band_level);

		sky_col = mix(sky_col, cloud_col, cloud_alpha);
	}

	// -- Color grading -----------------------------------------------------
	sky_col *= exposure;
	sky_col = apply_contrast(sky_col, contrast);
	sky_col = apply_saturation(sky_col, saturation);
	sky_col = apply_lift_gamma_gain(
			sky_col,
			lift.rgb,
			max(gamma_midtones.rgb * GAMMA_NEUTRAL, vec3(0.001)),
			gain.rgb);

	COLOR = max(sky_col, vec3(0.0));
}
