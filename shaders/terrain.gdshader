shader_type spatial;
render_mode diffuse_burley;

// Layer textures (Poly Haven PBR sets). Rock uses triplanar on slopes.
uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rgh : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_rgh : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rgh : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec3 grass_tint : source_color = vec3(1.0);
uniform vec3 dirt_tint : source_color = vec3(1.0);
uniform vec3 rock_tint : source_color = vec3(1.0);
uniform float grass_scale = 0.22;
uniform float dirt_scale = 0.25;
uniform float rock_scale = 0.12;
uniform float snow_scale = 0.2;
uniform float snow_amount = 0.0;
uniform float dirt_amount = 0.5;

varying vec3 wpos;
varying vec3 wnorm;

// Two rotated/offset samples blended by noise to hide tiling.
// (One copy per sampler setting: Godot requires matching hints per function.)
vec2 uv_b(vec2 uv) { return mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.71 + vec2(0.37, 0.19); }
vec4 untiled_col(sampler2D t, vec2 uv, float n) { return mix(texture(t, uv), texture(t, uv_b(uv)), smoothstep(0.35, 0.65, n)); }
vec4 untiled_nrm(sampler2D t, vec2 uv, float n) { return mix(texture(t, uv), texture(t, uv_b(uv)), smoothstep(0.35, 0.65, n)); }
vec4 untiled_rgh(sampler2D t, vec2 uv, float n) { return mix(texture(t, uv), texture(t, uv_b(uv)), smoothstep(0.35, 0.65, n)); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n_large = texture(noise_tex, wpos.xz * 0.008).r;
	float n_med = texture(noise_tex, wpos.xz * 0.045 + vec2(0.37, 0.11)).r;
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);

	vec2 uv_g = wpos.xz * grass_scale;
	vec2 uv_d = wpos.xz * dirt_scale;
	vec3 g_alb = untiled_col(grass_alb, uv_g, n_med).rgb * grass_tint;
	vec3 g_nrm = untiled_nrm(grass_nrm, uv_g, n_med).rgb;
	float g_rgh = untiled_rgh(grass_rgh, uv_g, n_med).r;
	vec3 d_alb = untiled_col(dirt_alb, uv_d, n_large).rgb * dirt_tint;
	vec3 d_nrm = untiled_nrm(dirt_nrm, uv_d, n_large).rgb;
	float d_rgh = untiled_rgh(dirt_rgh, uv_d, n_large).r;

	// Triplanar rock
	vec3 bw = pow(abs(wnorm), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 r_alb = (texture(rock_alb, wpos.zy * rock_scale).rgb * bw.x
		+ texture(rock_alb, wpos.xz * rock_scale).rgb * bw.y
		+ texture(rock_alb, wpos.xy * rock_scale).rgb * bw.z) * rock_tint;
	vec3 r_nrm = texture(rock_nrm, wpos.xz * rock_scale).rgb;
	float r_rgh = texture(rock_rgh, wpos.xz * rock_scale).r;

	float dirt_w = smoothstep(0.48, 0.7, n_med * 0.7 + n_large * 0.3) * dirt_amount;
	float rock_w = smoothstep(0.2, 0.42, slope + (n_med - 0.5) * 0.25);

	vec3 col = mix(g_alb, d_alb, dirt_w);
	vec3 nrm = mix(g_nrm, d_nrm, dirt_w);
	float rgh = mix(g_rgh, d_rgh, dirt_w);
	col = mix(col, r_alb, rock_w);
	nrm = mix(nrm, r_nrm, rock_w);
	rgh = mix(rgh, r_rgh, rock_w);

	if (snow_amount > 0.0) {
		vec2 uv_s = wpos.xz * snow_scale;
		float snow_w = snow_amount * smoothstep(0.62, 0.3, slope + (n_med - 0.5) * 0.35);
		col = mix(col, untiled_col(snow_alb, uv_s, n_med).rgb, snow_w);
		nrm = mix(nrm, untiled_nrm(snow_nrm, uv_s, n_med).rgb, snow_w);
		rgh = mix(rgh, 0.55, snow_w);
	}
	// Large-scale brightness variation breaks up repetition at distance.
	col *= mix(0.85, 1.12, n_large);

	ALBEDO = col;
	ROUGHNESS = rgh;
	SPECULAR = 0.35;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.0;
}
