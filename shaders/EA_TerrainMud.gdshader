shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Ground shader for the demo terrain: one tiling mud texture, varied by the mesh vertex colours.
//   R - wetness: darker, glossier mud
//   G - packed path: slightly lighter and greyer, where people walk between the graves
//   B - dry crust: lighter, rougher patches on the higher ground
//   A - standing water: very dark, almost mirror-like puddles in the hollows
// No splat map is needed - the terrain generator paints these weights into the vertices.

uniform sampler2D mud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float mud_scale = 2.4;
// A large second sample of the same texture, mixed in to break up the tiling pattern.
uniform float macro_scale = 0.31;
uniform float macro_amount : hint_range(0.0, 1.0) = 0.42;

uniform vec3 mud_tint = vec3(1.0, 1.0, 1.0);
uniform vec3 wet_tint = vec3(0.55, 0.52, 0.50);
uniform vec3 path_tint = vec3(1.16, 1.10, 1.02);
uniform vec3 dry_tint = vec3(1.28, 1.22, 1.10);
uniform vec3 puddle_tint = vec3(0.34, 0.36, 0.38);

uniform float dry_roughness : hint_range(0.0, 1.0) = 0.95;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.42;
uniform float puddle_roughness : hint_range(0.0, 1.0) = 0.12;

vec3 tiled(vec2 uv, float scale) {
	vec3 near_sample = texture(mud_tex, uv * scale).rgb;
	vec3 far_sample = texture(mud_tex, uv * scale * macro_scale).rgb;
	return mix(near_sample, far_sample, macro_amount);
}

void fragment() {
	vec4 w = COLOR;
	vec3 col = tiled(UV, mud_scale) * mud_tint;
	float grey = dot(col, vec3(0.333));
	// packed path: lighter and a touch less brown
	col = mix(col, mix(col, vec3(grey), 0.25) * path_tint, clamp(w.g, 0.0, 1.0));
	// dry crust on the rises
	col = mix(col, col * dry_tint, clamp(w.b, 0.0, 1.0));
	// wet mud in the low ground
	col = mix(col, col * wet_tint, clamp(w.r, 0.0, 1.0));
	// standing water
	col = mix(col, col * puddle_tint, clamp(w.a, 0.0, 1.0));
	float rough = mix(dry_roughness, wet_roughness, clamp(w.r, 0.0, 1.0));
	rough = mix(rough, puddle_roughness, clamp(w.a, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.15, 0.5, clamp(w.a, 0.0, 1.0));
}
