shader_type spatial;
render_mode diffuse_burley;

// Baked per vertex (see CharacterModel._bake_body):
//   COLOR.r = skin (head/neck), COLOR.g = gloves/feet, COLOR.b = rest-pose z
//   UV2 = rest-pose (x, y). The model is in T-pose, faces +Z, right side is -X.
// Suit details are drawn in rest-pose space, so they follow the body in any pose.
uniform sampler2D skin_alb : source_color, filter_linear_mipmap;
uniform sampler2D skin_nrm : hint_normal, filter_linear_mipmap;
uniform sampler2D skin_rgh : hint_default_white, filter_linear_mipmap;
uniform sampler2D cloth_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloth_var : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 suit_col : source_color = vec3(0.86, 0.6, 0.14);
uniform vec3 suit_col2 : source_color = vec3(0.5, 0.38, 0.16);
uniform vec3 gear_col : source_color = vec3(0.11, 0.1, 0.09);
uniform vec3 pad_col : source_color = vec3(0.2, 0.19, 0.17);
uniform float flash = 0.0;
uniform float shield_glow = 0.0;

varying vec4 region;
varying vec2 rest_xy;

void vertex() {
	region = COLOR;
	rest_xy = UV2;
}

float band(float v, float a, float b, float soft) {
	return smoothstep(a - soft, a, v) * (1.0 - smoothstep(b, b + soft, v));
}

void fragment() {
	float x = rest_xy.x;
	float ax = abs(x);
	float y = rest_xy.y;
	float z = (region.b - 0.5) * 0.5;
	float front = smoothstep(-0.01, 0.03, z);

	float skin = smoothstep(0.3, 0.7, region.r) * smoothstep(1.5, 1.54, y);
	float glove = max(smoothstep(0.3, 0.7, region.g), 1.0 - smoothstep(0.26, 0.3, y)) * (1.0 - skin);

	// Cloth base: two-tone (darker shoulder yoke + sides), fabric variation.
	vec2 cuv = vec2(x + z, y) * 6.0;
	float v = texture(cloth_var, cuv * 0.35).r;
	float yoke = smoothstep(1.36, 1.4, y) * (1.0 - smoothstep(0.26, 0.3, ax));
	vec3 cloth = mix(suit_col, suit_col2, yoke * 0.55) * mix(0.75, 1.05, v);

	// Gear: belt, harness straps, collar, cuffs, zipper; pads: knees, elbows.
	float belt = band(y, 0.97, 1.06, 0.004);
	float buckle = belt * band(ax, 0.0, 0.025, 0.003) * front;
	float strap_x = 0.085 + (1.48 - y) * 0.05;
	float straps = band(ax, strap_x - 0.022, strap_x + 0.022, 0.004) * band(y, 1.06, 1.5, 0.004) * (1.0 - smoothstep(0.17, 0.2, ax) * step(y, 1.4));
	float chest_bar = band(y, 1.24, 1.28, 0.004) * front * step(ax, 0.12);
	float collar = band(y, 1.47, 1.53, 0.006) * step(ax, 0.12);
	float cuffs = band(ax, 0.6, 0.65, 0.004) + band(y, 0.27, 0.32, 0.005) * (1.0 - step(0.3, ax));
	float zipper = band(ax, 0.0, 0.006, 0.002) * band(y, 1.05, 1.47, 0.004) * front;
	float knee = band(y, 0.42, 0.58, 0.01) * smoothstep(0.0, 0.04, z) * step(ax, 0.2);
	float elbow = band(ax, 0.44, 0.48, 0.006);
	float pocket = band(y, 0.72, 0.86, 0.006) * band(ax, 0.13, 0.19, 0.006);
	float gear = clamp(belt + straps + chest_bar + collar + cuffs, 0.0, 1.0);
	float pads = clamp(knee * 0.3 + elbow * 0.8 + pocket * 0.6, 0.0, 1.0);
	cloth = mix(cloth, pad_col * mix(0.8, 1.1, v), pads);
	cloth = mix(cloth, gear_col * mix(0.85, 1.15, v), gear);
	cloth = mix(cloth, vec3(0.35, 0.33, 0.3), buckle);
	cloth *= 1.0 - zipper * 0.6;

	float suit = 1.0 - skin - glove;
	vec3 skin_c = texture(skin_alb, UV).rgb;
	vec3 glove_c = gear_col * 1.2 * mix(0.8, 1.1, v);
	ALBEDO = skin_c * skin + cloth * suit + glove_c * glove + vec3(flash);
	ROUGHNESS = texture(skin_rgh, UV).r * skin + mix(0.9, 0.6, gear) * suit + 0.65 * glove;
	METALLIC = buckle * 0.4 * suit;
	vec3 n_skin = texture(skin_nrm, UV).rgb;
	vec3 n_cloth = texture(cloth_nrm, cuv).rgb;
	NORMAL_MAP = mix(n_cloth, n_skin, skin);
	NORMAL_MAP_DEPTH = mix(mix(1.2, 0.4, gear), 1.0, skin);
	SPECULAR = 0.35;
	// Energy shield shimmer: fresnel rim + scanlines, cyan.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float scan = 0.6 + 0.4 * sin(UV2.y * 90.0 + TIME * 12.0);
	EMISSION = vec3(0.25, 0.7, 1.0) * shield_glow * (0.35 + fres * 2.5) * scan * 2.0;
}
