shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 base_col : source_color = vec3(0.18, 0.22, 0.08);
uniform vec3 tip_col : source_color = vec3(0.62, 0.58, 0.32);
uniform float wind_strength = 0.18;
uniform float wind_speed = 1.6;

varying float tip;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tip = 1.0 - UV.y;
	float w = tip * tip;
	float gust = sin(TIME * 0.35 + wp.x * 0.04) * 0.5 + 0.5;
	VERTEX.x += sin(TIME * wind_speed + wp.x * 0.35 + wp.z * 0.21) * wind_strength * w * (0.5 + gust);
	VERTEX.z += cos(TIME * wind_speed * 0.8 + wp.z * 0.3) * wind_strength * 0.6 * w * (0.5 + gust);
}

void fragment() {
	vec3 c = mix(base_col, tip_col, tip) * COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	BACKLIGHT = c * 0.6;
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.7));
	AO = mix(0.35, 1.0, tip);
	AO_LIGHT_AFFECT = 0.6;
}
