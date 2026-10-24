shader_type canvas_item;

uniform float intensity = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.02, 0.0, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.5, 1.0));
	float v = smoothstep(0.3, 0.95, d);
	COLOR = vec4(tint.rgb, clamp(v * intensity * 1.6, 0.0, 0.85));
}
