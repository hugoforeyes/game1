shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(1.0, 0.72, 0.18, 1.0);
uniform vec2 outline_step = vec2(0.006, 0.006);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float center_alpha = texture(TEXTURE, UV).a;
	float neighbor_alpha = 0.0;
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( outline_step.x, 0.0)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-outline_step.x, 0.0)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(0.0,  outline_step.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(0.0, -outline_step.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( outline_step.x,  outline_step.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-outline_step.x,  outline_step.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( outline_step.x, -outline_step.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-outline_step.x, -outline_step.y)).a);
	float edge = clamp(neighbor_alpha - center_alpha, 0.0, 1.0);
	COLOR = vec4(
		outline_color.rgb,
		edge * outline_color.a * opacity
	);
}
