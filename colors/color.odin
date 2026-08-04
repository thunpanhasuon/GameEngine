package colors

Lofi_Color :: enum {
	Cream,     // warm off-white background
	Dusk,      // muted purple
	Mocha,     // soft brown
	Sage,      // dusty green
	Rust,      // faded orange-red
	Slate,     // muted blue-gray
	Charcoal,  // near-black for text/outlines
}

/* rgba, straight to gl.Uniform4fv / gl.ClearColor */
lofi_palette := [Lofi_Color][4]f32{
	.Cream    = {0.929, 0.878, 0.784, 1.0},
	.Dusk     = {0.482, 0.408, 0.510, 1.0},
	.Mocha    = {0.431, 0.310, 0.247, 1.0},
	.Sage     = {0.482, 0.553, 0.427, 1.0},
	.Rust     = {0.710, 0.353, 0.235, 1.0},
	.Slate    = {0.349, 0.396, 0.459, 1.0},
	.Charcoal = {0.157, 0.141, 0.133, 1.0},
}

rgba :: proc(color: Lofi_Color) -> [4]f32 {
	return lofi_palette[color]
}
