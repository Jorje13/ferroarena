shader_type sky;

uniform vec3 top_col : source_color = vec3(0.30, 0.50, 0.78);
uniform vec3 horizon_col : source_color = vec3(0.78, 0.80, 0.80);
uniform vec3 ground_col : source_color = vec3(0.35, 0.33, 0.30);
uniform vec3 cloud_col : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.62, 0.66, 0.72);
uniform float cloud_cover = 0.45;
uniform float energy = 1.0;
uniform float sun_disc = 1.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_col, top_col, smoothstep(0.0, 0.55, h));
	col = mix(col, ground_col, smoothstep(0.0, -0.2, h));

	float sun_amt = 0.0;
	if (LIGHT0_ENABLED) {
		float sd = clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0);
		float ang = acos(sd);
		sun_amt = exp(-ang * 5.0);
		col += LIGHT0_COLOR * 0.25 * sun_amt;
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (1.0 - smoothstep(0.012, 0.016, ang)) * 6.0 * sun_disc;
	}

	if (h > -0.02) {
		vec2 uv = d.xz / (max(h, 0.0) + 0.12);
		float n = texture(cloud_noise, uv * 0.06).r * 0.65
			+ texture(cloud_noise, uv * 0.19 + vec2(0.31, 0.17)).r * 0.35;
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n);
		c *= smoothstep(-0.02, 0.18, h);
		vec3 cc = mix(cloud_shadow, cloud_col, smoothstep(0.3, 0.9, n));
		cc += (LIGHT0_ENABLED ? LIGHT0_COLOR * sun_amt * 0.4 : vec3(0.0));
		col = mix(col, cc, c * 0.9);
	}
	COLOR = col * energy;
}
