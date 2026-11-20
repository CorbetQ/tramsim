extends SceneTree
var fails := 0
func check(ok: bool, message: String) -> void:
	if not ok:fails+=1;printerr("ECHEC: ",message)
	else:print("ok: ",message)
func _initialize() -> void:
	if not "TramSimFeatureFixture" in OS.get_user_data_dir():
		printerr("ECHEC: run with isolated XDG_DATA_HOME ending in TramSimFeatureFixture");quit(2);return
	root.disable_3d=true;run.call_deferred()
func run() -> void:
	var fixture := SaveGame.default_data()
	fixture.settings.home_bg=false;fixture.settings.intro=false;fixture.settings.tutorial_done=true;fixture.settings.ai_trams=false
	fixture["unknown_extension"]={"preserve":true}
	SaveGame.save_data(fixture)
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main);await process_frame
	main.menu_city="Angers";main._build_menu();await process_frame
	var has_passenger := false
	for label in main.find_children("*","Label",true,false):
		if label.text=="Mode passager":has_passenger=true
	check(has_passenger,"actual home offers passenger mode")
	main._open_settings()
	var weather_choice: TouchChoice
	for button in main.settings_layer.find_children("*","Button",true,false):
		if button is TouchChoice and button.choice_title=="Météo":weather_choice=button
	check(weather_choice!=null,"actual settings expose weather")
	if weather_choice!=null:weather_choice.select(3);weather_choice.item_selected.emit(3)
	main._close_settings()
	check(main.save.settings.get("weather")=="storm","weather selector stores selected preset")
	main.free_mode=true;main.net_path="res://data/free/angers.json"
	main.vehicle=VehicleLibrary.default_for(CityDataStore.document(main.net_path));main.start_station={}
	await main._start(false)
	check(main.session!=null and main.weather.preset=="storm" and is_instance_valid(main.weather_view),"actual driving launch wires weather and visual view")
	for i in 3:await process_frame
	main._persist()
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SaveGame.DEFAULT_PATH))
	check(saved.free.has("weather") and saved.free.weather.version==1,"actual free checkpoint stores versioned weather state")
	check(saved.unknown_extension.preserve,"existing unknown save data preserved")
	print("TOTAL_ECHECS|",fails)
	await main._quit_safely()
