shader_type canvas_item;

uniform vec4 draw_color : source_color = vec4(1.0, 1.0, 1.0, 0.55);

void fragment() {
	COLOR = draw_color;
}
