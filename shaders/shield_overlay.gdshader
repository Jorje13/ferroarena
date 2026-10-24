shader_type spatial;
// Additive pass drawn over the raider's PBR materials: energy-shield shimmer
// (fresnel rim + moving scanlines, cyan) and the white hit flash.
render_mode unshaded, blend_add, depth_draw_never, cull_back, depth_test_default, shadows_disabled;

uniform float shield_glow = 0.0;
uniform float flash = 0.0;

varying float v_height;

void vertex() {
	v_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float scan = 0.6 + 0.4 * sin(v_height * 90.0 + TIME * 12.0);
	vec3 c = vec3(0.25, 0.7, 1.0) * shield_glow * (0.35 + fres * 2.5) * scan * 1.6;
	ALBEDO = c + vec3(flash) * 0.6;
}
