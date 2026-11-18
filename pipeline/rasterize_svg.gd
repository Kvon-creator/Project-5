extends SceneTree
## Rasterise SVG files to PNG with Godot's own SVG renderer (ThorVG), so the
## art pipeline needs no Python SVG library. Used by pipeline/item_icons.py.
##
##   godot --headless --path . --script res://pipeline/rasterize_svg.gd -- \
##         <size_px> <out_dir> <file.svg> [<file.svg> ...]
##
## Each SVG is rendered so its viewBox fills a size_px square and saved as
## <out_dir>/<name>.png.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: <size_px> <out_dir> <file.svg>...")
		quit(2)
		return
	var size := int(args[0])
	var out_dir := args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var failed := 0
	for i in range(2, args.size()):
		var path := args[i]
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			push_error("cannot read %s" % path)
			failed += 1
			continue
		# game-icons.net SVGs are drawn on a 512 x 512 viewBox.
		var img := Image.new()
		var err := img.load_svg_from_string(text, float(size) / 512.0)
		if err != OK:
			push_error("cannot rasterise %s (%d)" % [path, err])
			failed += 1
			continue
		var out := out_dir.path_join(path.get_file().get_basename() + ".png")
		img.save_png(out)
		print("  ", out, " ", img.get_size())
	quit(1 if failed > 0 else 0)
