class_name LiveryPainter
extends RefCounted
## Small generated atlases: paint is produced once per scheme, never per frame.
## Keep cab/interior swatches and the original black face mask intact.
static var _textures: Dictionary = {}
static var _layouts: Dictionary = {}

static func reset_cache() -> void:
	_textures.clear()

static func layouts() -> Dictionary:
	if _layouts.is_empty(): _layouts = JSON.parse_string(FileAccess.get_file_as_string("res://data/rolling_stock/livery_layouts.json"))
	return _layouts

static func texture(source: Texture2D, design: Dictionary, entry: Dictionary, part_index: int = -1) -> Texture2D:
	if source == null or not layouts().has(str(entry.id)): return source
	var key := str(source.get_instance_id()) + JSON.stringify(design).sha256_text()
	if _textures.has(key): return _textures[key]
	var image := source.get_image().duplicate() as Image
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var width := mini(1024, image.get_width())
	image.resize(width, width / 2, Image.INTERPOLATE_LANCZOS)
	var height := image.get_height()
	var side_h := roundi(height * 0.625)
	var colors: Dictionary = design.colors
	image.fill_rect(Rect2i(0,0,width,side_h), Color(colors.base))
	image.fill_rect(Rect2i(0,0,width,roundi(side_h * (3.4-2.75)/3.4)), Color(colors.roof))
	image.fill_rect(Rect2i(0,roundi(side_h*(3.4-0.45)/3.4),width,side_h-roundi(side_h*(3.4-0.45)/3.4)), Color(colors.skirt))
	for band in design.bands:
		if not band.enabled: continue
		var y := roundi(side_h*(3.4-float(band.y)-float(band.width))/3.4)
		var rect := Rect2i(0,y,width,maxi(1,roundi(side_h*float(band.width)/3.4)))
		image.fill_rect(rect.intersection(Rect2i(0,0,width,side_h)), Color(band.color))
	# Windows/doors remain readable in the low-detail atlases too.
	var plan := StockGeometry.apply(TramModel.plan(str(entry.family)),entry)
	var total := 0.0
	for module in plan.modules: total += float(module.length_m)
	var physical_total:=float(entry.length)
	if part_index>=0 and part_index<plan.modules.size():
		var selected:Dictionary=plan.modules[part_index]
		physical_total=physical_total*float(selected.length_m)/total
		plan=plan.duplicate(true);plan.modules=[selected];total=float(selected.length_m)
	var offset := 0.0
	for module in plan.modules:
		for window in module.get("windows", []):
			_side_rect(image, width, side_h, (offset+float(window.z0_m))/total, (offset+float(window.z1_m))/total, 1.05, 2.45, Color(colors.window))
		for door in module.get("doors", []):
			var center := (offset+float(door.z_m))/total
			var half := float(door.width_m)/physical_total*0.5
			_side_rect(image,width,side_h,center-half,center+half,0.36,2.4,Color(colors.door))
			_side_rect(image,width,side_h,center-half+0.003,center+half-0.003,0.65,2.28,Color(colors.window))
		offset += float(module.length_m)
	# The front is a distinct atlas region. Preserve dark mask/optical details.
	var front := Rect2i(0,roundi(height*0.625),roundi(width*0.1875),roundi(height*0.375))
	for y in range(front.position.y,front.end.y):
		for x in range(front.end.x):
			if image.get_pixel(x,y).get_luminance() < 0.12: continue
			var color := Color(colors.front)
			var physical_y := 3.4 * (1.0-float(y-front.position.y)/maxf(front.size.y,1))
			for band in design.bands:
				if band.enabled and physical_y >= float(band.y) and physical_y <= float(band.y)+float(band.width): color = Color(band.color)
			image.set_pixel(x,y,color)
	var layout: Dictionary = layouts()[str(entry.id)]
	for zone in layout.swatches:
		if not colors.has(zone): continue
		var point: Array = layout.swatches[zone]
		var center := Vector2i(roundi(float(point[0])*width/4096.0),roundi(float(point[1])*height/2048.0))
		var radius := maxi(1,roundi(width*0.003))
		image.fill_rect(Rect2i(center-Vector2i.ONE*radius,Vector2i.ONE*radius*2),Color(colors[zone]))
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	if _textures.size() >= 8: _textures.erase(_textures.keys()[0])
	_textures[key] = result
	return result

static func _side_rect(image: Image, width: int, height: int, x0: float, x1: float, y0: float, y1: float, color: Color) -> void:
	var rect := Rect2i(roundi(x0*width),roundi((3.4-y1)/3.4*height),maxi(1,roundi((x1-x0)*width)),maxi(1,roundi((y1-y0)/3.4*height)))
	image.fill_rect(rect.intersection(Rect2i(0,0,width,height)),color)

static func add_labels(rig, livery: Dictionary) -> void:
	var design: Dictionary = livery.get("custom_livery", {})
	var text := str(design.get("label", ""))
	if text == "": return
	var middle: int = rig.modules.size()/2
	var parent: Node3D = rig.hd.lods[0][middle] if rig.hd != null else rig.modules[middle]
	for side in [-1,1]:
		var label := Label3D.new(); label.name = "CustomLiveryLabel" + str(side)
		label.text = text; label.font_size = 48; label.pixel_size = 0.0025; label.outline_size = 0
		label.modulate = Color.BLACK if (livery.base as Color).get_luminance() > 0.45 else Color.WHITE
		label.position = Vector3(side*(float(livery.width)/2+0.04),0.75,0); label.rotation.y = side*PI/2
		parent.add_child(label)
