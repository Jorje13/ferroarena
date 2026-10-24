shader_type canvas_item;
// Final image polish (drawn under the HUD): sharpening to counter TAA softness,
// subtle lens chromatic aberration, vignette and film grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float sharpen = 0.4;
uniform float aberration = 0.0025;
uniform float vignette = 0.3;
uniform float grain = 0.022;
uniform float focus = 0.0; // 0..1: aiming down the sights (soft edges, sharp centre)

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec2 off = d * aberration * r2 * 4.0;
	// Peripheral softness: sample a blurrier mip towards the edges while aiming.
	float edge = smoothstep(0.22, 0.6, length(d * vec2(1.0, 1.15)));
	float lod = focus * edge * 1.1;
	vec3 col = vec3(textureLod(screen_tex, uv + off, lod).r, textureLod(screen_tex, uv, lod).g, textureLod(screen_tex, uv - off, lod).b);
	vec2 pxl = px * (1.0 + lod);
	vec3 blur = (textureLod(screen_tex, uv + vec2(pxl.x, 0.0), lod).rgb + textureLod(screen_tex, uv - vec2(pxl.x, 0.0), lod).rgb
		+ textureLod(screen_tex, uv + vec2(0.0, pxl.y), lod).rgb + textureLod(screen_tex, uv - vec2(0.0, pxl.y), lod).rgb) * 0.25;
	col += (col - blur) * sharpen * (1.0 - clamp(lod / 1.1, 0.0, 1.0));
	col *= 1.0 - vignette * smoothstep(0.1, 0.6, r2 * 2.0);
	float n = fract(sin(dot(uv * vec2(12.9898, 78.233) + fract(TIME * 7.13), vec2(1.0, 1.7))) * 43758.5453);
	col += (n - 0.5) * grain;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
