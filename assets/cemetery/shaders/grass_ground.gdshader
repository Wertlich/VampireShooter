shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// World-space tiled grass for the cemetery floor. Two scales break up the
// repetition, and a low-frequency sample introduces broad moss/dirt patches.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_scale = 0.145;
uniform float macro_scale = 0.018;
uniform vec3 tint : source_color = vec3(0.82, 0.9, 0.7);
uniform float roughness : hint_range(0.0, 1.0) = 0.97;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.55;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv_near = world_pos.xz * tile_scale;
	vec2 uv_far = world_pos.xz * tile_scale * 0.19 + vec2(0.37, 0.61);
	vec2 uv_macro = world_pos.xz * macro_scale + vec2(0.13, 0.44);
	vec3 near_col = texture(grass_tex, uv_near).rgb;
	vec3 far_col = texture(grass_tex, uv_far).rgb;
	vec3 macro = texture(grass_tex, uv_macro).rgb;
	vec3 col = mix(near_col, far_col, 0.34) * tint;
	col *= 0.76 + macro.g * 0.42;
	float patch = smoothstep(0.52, 0.78, macro.r);
	col = mix(col, col * vec3(0.55, 0.62, 0.48), patch * 0.34);
	float dry = smoothstep(0.72, 0.92, macro.b);
	col = mix(col, col * vec3(1.18, 1.06, 0.78), dry * 0.18);
	ALBEDO = col;
	NORMAL_MAP = texture(grass_normal, uv_near * 0.55).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = roughness;
	SPECULAR = 0.16;
}
