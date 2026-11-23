extends "res://tests/audit/family_front_shots.gd"
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()>0:out=args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size=Vector2i(1920,640);root.content_scale_size=root.size
	var ids:Array=["angers__citadis_302","angers__citadis_x05","nantes__citadis_x05_nantes"]
	for mobile in [false,true]:
		DayNight.low_quality=mobile;StockHD.reset_cache()
		var profile:="mobile" if mobile else "pc"
		await capture(ids,3,"roof_front",profile+"-roof-front")
		await capture(ids,3,"roof_rear",profile+"-roof-rear")
	StockHD.reset_cache();quit()
