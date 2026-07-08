extends Node3D

const SAVE_PATH := "user://levels/free_model_level.json"
const EXPORT_SCENE_DIR := "res://scenes/exports"
const EXPORT_SCENE_BASENAME := "exported_level"
const EXPORT_RUNTIME_SCRIPT_PATH := "res://scripts/exported_level_runtime.gd"
const GROUND_SIZE := 200.0
const MIN_SCALE := 0.1
const MAX_SCALE := 5.0
const SLIDER_MIN := -0.9
const SLIDER_MAX := 4.0
const ROTATION_MIN := -180.0
const ROTATION_MAX := 180.0
const KEY_ROTATION_SPEED := 90.0
const KEY_SCALE_SPEED := 0.6
const KEY_HEIGHT_SPEED := 2.0
const CAMERA_ORBIT_SENSITIVITY := 0.006
const CAMERA_PAN_SENSITIVITY := 0.035
const CAMERA_MIN_PITCH := -1.35
const CAMERA_MAX_PITCH := -0.12
const CAMERA_MIN_DISTANCE := 1.0
const CAMERA_MAX_DISTANCE := 100.0
const ASSET_CATALOG_PATH := "res://data/asset_catalog.json"

const FALLBACK_ASSETS := [
	{"id": "tree_1", "name": "树 1", "path": "res://assets/models/starter/tree_1.fbx", "scale": 1.0},
	{"id": "tree_2", "name": "树 2", "path": "res://assets/models/starter/tree_2.fbx", "scale": 1.0},
	{"id": "rock_1", "name": "岩石", "path": "res://assets/models/starter/rock_1.fbx", "scale": 1.0},
	{"id": "stone_1", "name": "石块", "path": "res://assets/models/starter/stone_1.fbx", "scale": 1.0},
	{"id": "plant_1", "name": "植物", "path": "res://assets/models/starter/plant_1.fbx", "scale": 1.0},
	{"id": "bush_1", "name": "灌木", "path": "res://assets/models/starter/bush_1.fbx", "scale": 1.0},
	{"id": "log_1", "name": "木头", "path": "res://assets/models/starter/log_1.fbx", "scale": 1.0},
	{"id": "terrain_1", "name": "地形块", "path": "res://assets/models/starter/terrain_1.fbx", "scale": 1.0}
]

enum EditMode {
	PLACE,
	SELECT
}

var objects: Array[Dictionary] = []
var object_nodes: Array[Node3D] = []
var asset_catalog: Array[Dictionary] = []
var asset_categories: Array[String] = []
var selected_asset_id: String = "tree_1"
var selected_category: String = ""
var selected_object_index: int = -1
var edit_mode: int = EditMode.PLACE
var brush_rotation_y: float = 0.0
var brush_scale: float = 1.0
var snap_enabled: bool = false
var snap_step: float = 0.5
var is_dragging_selected: bool = false
var is_orbiting_camera: bool = false
var is_panning_camera: bool = false
var pressed_object_index: int = -1
var drag_offset: Vector3 = Vector3.ZERO
var copied_object_data: Dictionary = {}

var camera_distance: float = 22.0
var camera_angle: Vector2 = Vector2(deg_to_rad(-48.0), deg_to_rad(45.0))
var camera_target: Vector3 = Vector3.ZERO

var camera: Camera3D
var object_root: Node3D
var cursor: MeshInstance3D
var selection_marker: MeshInstance3D
var status_label: Label
var mode_label: Label
var asset_label: Label
var transform_label: Label
var category_filter: OptionButton
var asset_list: ItemList
var rotation_slider: HSlider
var rotation_value_input: LineEdit
var scale_slider: HSlider
var scale_value_input: LineEdit

var material_ground: StandardMaterial3D = StandardMaterial3D.new()
var material_cursor: StandardMaterial3D = StandardMaterial3D.new()
var material_selection: StandardMaterial3D = StandardMaterial3D.new()
var material_placeholder: StandardMaterial3D = StandardMaterial3D.new()
var building_material_cache: Dictionary = {}


func _ready() -> void:
	_load_asset_catalog()
	_build_materials()
	_build_world()
	_build_ui()
	_update_camera()
	_update_labels()
	_update_status("左键点物件选中并拖拽移动；W/S 调整高度，Q/E、Z/X 连续控制旋转和缩放。")
	call_deferred("_load_saved_level_on_startup")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if (is_orbiting_camera or is_dragging_selected) and mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_handle_left_release(mouse_event.position)
			return
		if is_panning_camera and mouse_event.button_index == MOUSE_BUTTON_MIDDLE and not mouse_event.pressed:
			_stop_camera_pan()
			return
		if _is_pointer_over_ui() and not is_dragging_selected:
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if mouse_event.alt_pressed:
					_start_camera_orbit()
				else:
					_handle_left_press(mouse_event.position)
			else:
				_handle_left_release(mouse_event.position)
		elif mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			if mouse_event.pressed and mouse_event.alt_pressed:
				_start_camera_pan()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_select_object(-1)
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = max(CAMERA_MIN_DISTANCE, camera_distance - 1.0)
			_update_camera()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = min(CAMERA_MAX_DISTANCE, camera_distance + 1.0)
			_update_camera()

	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if is_orbiting_camera:
			_orbit_camera(motion.relative)
			return
		if is_panning_camera:
			_pan_camera(motion.relative)
			return
		if _is_pointer_over_ui() and not is_dragging_selected:
			return
		var hit: Dictionary = _mouse_to_ground(motion.position)
		cursor.visible = bool(hit["valid"])
		if bool(hit["valid"]):
			cursor.position = hit["position"] + Vector3(0.0, 0.025, 0.0)
			if pressed_object_index >= 0:
				_drag_selected_to(hit["position"])

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			_handle_key_event(key_event)


func _process(delta: float) -> void:
	var height_handled: bool = _process_height_shortcuts(delta)
	var move: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) and not height_handled:
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S) and not height_handled:
		move.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0

	if move != Vector3.ZERO:
		camera_target += move.normalized() * delta * 8.0
		var half: float = GROUND_SIZE * 0.5
		camera_target.x = clamp(camera_target.x, -half, half)
		camera_target.z = clamp(camera_target.z, -half, half)
		_update_camera()

	_process_transform_shortcuts(delta)


func _build_materials() -> void:
	_configure_material(material_ground, Color(0.36, 0.48, 0.36))
	_configure_material(material_cursor, Color(1.0, 1.0, 1.0, 0.24), true)
	_configure_material(material_selection, Color(1.0, 0.78, 0.18, 0.42), true)
	_configure_material(material_placeholder, Color(0.25, 0.55, 0.92))


func _configure_material(material: StandardMaterial3D, color: Color, transparent: bool = false) -> void:
	material.albedo_color = color
	material.roughness = 0.72
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _build_world() -> void:
	var light: DirectionalLight3D = _create_scene_light()
	add_child(light)

	var ambient: WorldEnvironment = _create_scene_environment()
	add_child(ambient)

	camera = Camera3D.new()
	camera.current = true
	add_child(camera)

	var ground: MeshInstance3D = _create_scene_ground()
	add_child(ground)

	object_root = Node3D.new()
	object_root.name = "Objects"
	add_child(object_root)

	cursor = MeshInstance3D.new()
	cursor.name = "PlacementCursor"
	var cursor_mesh: CylinderMesh = CylinderMesh.new()
	cursor_mesh.top_radius = 0.45
	cursor_mesh.bottom_radius = 0.45
	cursor_mesh.height = 0.04
	cursor_mesh.radial_segments = 32
	cursor.mesh = cursor_mesh
	cursor.material_override = material_cursor
	cursor.visible = false
	add_child(cursor)

	selection_marker = MeshInstance3D.new()
	selection_marker.name = "SelectionMarker"
	var marker_mesh: CylinderMesh = CylinderMesh.new()
	marker_mesh.top_radius = 0.85
	marker_mesh.bottom_radius = 0.85
	marker_mesh.height = 0.05
	marker_mesh.radial_segments = 48
	selection_marker.mesh = marker_mesh
	selection_marker.material_override = material_selection
	selection_marker.visible = false
	add_child(selection_marker)


func _create_scene_light() -> DirectionalLight3D:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	light.light_energy = 2.8
	return light


func _create_scene_environment() -> WorldEnvironment:
	var ambient: WorldEnvironment = WorldEnvironment.new()
	ambient.name = "WorldEnvironment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.75, 0.86, 0.92)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.74, 0.78)
	environment.ambient_light_energy = 0.9
	ambient.environment = environment
	return ambient


func _create_scene_ground() -> MeshInstance3D:
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh: BoxMesh = BoxMesh.new()
	ground_mesh.size = Vector3(GROUND_SIZE, 0.08, GROUND_SIZE)
	ground.mesh = ground_mesh
	ground.position.y = -0.04
	var ground_material: StandardMaterial3D = material_ground.duplicate(true) as StandardMaterial3D
	ground_material.resource_local_to_scene = true
	ground.material_override = ground_material
	return ground


func _build_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(300, 0)
	canvas.add_child(panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)

	var title: Label = Label.new()
	title.text = "自由模型地编"
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)

	mode_label = Label.new()
	content.add_child(mode_label)

	asset_label = Label.new()
	content.add_child(asset_label)

	transform_label = Label.new()
	transform_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(transform_label)

	var mode_buttons: HBoxContainer = HBoxContainer.new()
	mode_buttons.add_theme_constant_override("separation", 8)
	content.add_child(mode_buttons)

	var place_button: Button = Button.new()
	place_button.text = "放置"
	place_button.pressed.connect(_set_mode.bind(EditMode.PLACE))
	mode_buttons.add_child(place_button)

	var select_button: Button = Button.new()
	select_button.text = "选择"
	select_button.pressed.connect(_set_mode.bind(EditMode.SELECT))
	mode_buttons.add_child(select_button)

	var snap_button: Button = Button.new()
	snap_button.text = "吸附"
	snap_button.pressed.connect(_toggle_snap)
	mode_buttons.add_child(snap_button)

	var asset_title: Label = Label.new()
	asset_title.text = "模型资产"
	content.add_child(asset_title)

	category_filter = OptionButton.new()
	category_filter.item_selected.connect(_select_category_by_index)
	content.add_child(category_filter)

	asset_list = ItemList.new()
	asset_list.custom_minimum_size = Vector2(280, 170)
	asset_list.select_mode = ItemList.SELECT_SINGLE
	asset_list.item_selected.connect(_select_asset_by_index)
	content.add_child(asset_list)

	_refresh_category_filter()

	var actions: GridContainer = GridContainer.new()
	actions.columns = 3
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	content.add_child(actions)

	var save_button: Button = Button.new()
	save_button.text = "保存"
	save_button.pressed.connect(_save_level)
	actions.add_child(save_button)

	var export_button: Button = Button.new()
	export_button.text = "导出"
	export_button.pressed.connect(_export_scene)
	actions.add_child(export_button)

	var load_button: Button = Button.new()
	load_button.text = "加载"
	load_button.pressed.connect(_load_level)
	actions.add_child(load_button)

	var clear_button: Button = Button.new()
	clear_button.text = "清空"
	clear_button.pressed.connect(_clear_level)
	actions.add_child(clear_button)

	var delete_button: Button = Button.new()
	delete_button.text = "删除"
	delete_button.pressed.connect(_delete_selected)
	actions.add_child(delete_button)

	var duplicate_button: Button = Button.new()
	duplicate_button.text = "复制"
	duplicate_button.pressed.connect(_copy_selected)
	actions.add_child(duplicate_button)

	var paste_button: Button = Button.new()
	paste_button.text = "粘贴"
	paste_button.pressed.connect(_paste_copied)
	actions.add_child(paste_button)

	var sample_button: Button = Button.new()
	sample_button.text = "示例"
	sample_button.pressed.connect(_build_sample_level)
	actions.add_child(sample_button)

	var transform_title: Label = Label.new()
	transform_title.text = "选中物件变换"
	content.add_child(transform_title)

	var reset_button: Button = Button.new()
	reset_button.text = "归正"
	reset_button.pressed.connect(_reset_selected_transform)
	content.add_child(reset_button)

	var rotation_row: HBoxContainer = HBoxContainer.new()
	rotation_row.add_theme_constant_override("separation", 8)
	content.add_child(rotation_row)

	var rotation_title: Label = Label.new()
	rotation_title.text = "旋转"
	rotation_row.add_child(rotation_title)

	rotation_slider = HSlider.new()
	rotation_slider.min_value = ROTATION_MIN
	rotation_slider.max_value = ROTATION_MAX
	rotation_slider.step = 1.0
	rotation_slider.value = 0.0
	rotation_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotation_slider.value_changed.connect(_set_current_rotation)
	rotation_row.add_child(rotation_slider)

	rotation_value_input = LineEdit.new()
	rotation_value_input.custom_minimum_size = Vector2(72, 0)
	rotation_value_input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rotation_value_input.text_submitted.connect(_apply_rotation_input)
	rotation_value_input.focus_exited.connect(_apply_rotation_input_from_field)
	rotation_value_input.focus_entered.connect(_select_rotation_input_text)
	rotation_row.add_child(rotation_value_input)

	var scale_row: HBoxContainer = HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 8)
	content.add_child(scale_row)

	var scale_title: Label = Label.new()
	scale_title.text = "缩放"
	scale_row.add_child(scale_title)

	scale_slider = HSlider.new()
	scale_slider.min_value = SLIDER_MIN
	scale_slider.max_value = SLIDER_MAX
	scale_slider.step = 0.01
	scale_slider.value = 0.0
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.value_changed.connect(_set_current_scale)
	scale_row.add_child(scale_slider)

	scale_value_input = LineEdit.new()
	scale_value_input.custom_minimum_size = Vector2(72, 0)
	scale_value_input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_value_input.text_submitted.connect(_apply_scale_input)
	scale_value_input.focus_exited.connect(_apply_scale_input_from_field)
	scale_value_input.focus_entered.connect(_select_scale_input_text)
	scale_row.add_child(scale_value_input)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status_label)


func _handle_key_event(key_event: InputEventKey) -> void:
	if key_event.ctrl_pressed and key_event.keycode == KEY_C:
		_copy_selected()
		return
	if key_event.ctrl_pressed and key_event.keycode == KEY_V:
		_paste_copied()
		return
	_handle_key(key_event.keycode)


func _handle_key(keycode: int) -> void:
	match keycode:
		KEY_TAB:
			_set_mode(EditMode.SELECT if edit_mode == EditMode.PLACE else EditMode.PLACE)
		KEY_DELETE:
			_delete_selected()
		KEY_ESCAPE:
			_select_object(-1)


func _process_transform_shortcuts(delta: float) -> void:
	if _is_pointer_over_ui():
		return

	var rotation_delta: float = 0.0
	if Input.is_key_pressed(KEY_Q):
		rotation_delta += KEY_ROTATION_SPEED * delta
	if Input.is_key_pressed(KEY_E):
		rotation_delta -= KEY_ROTATION_SPEED * delta
	if rotation_delta != 0.0:
		_add_current_rotation(rotation_delta)

	var scale_delta: float = 0.0
	if Input.is_key_pressed(KEY_X):
		scale_delta += KEY_SCALE_SPEED * delta
	if Input.is_key_pressed(KEY_Z):
		scale_delta -= KEY_SCALE_SPEED * delta
	if scale_delta != 0.0:
		_add_current_scale(scale_delta)


func _process_height_shortcuts(delta: float) -> bool:
	if _is_pointer_over_ui():
		return false
	if selected_object_index < 0 or selected_object_index >= objects.size():
		return false

	var height_delta: float = 0.0
	if Input.is_key_pressed(KEY_W):
		height_delta += KEY_HEIGHT_SPEED * delta
	if Input.is_key_pressed(KEY_S):
		height_delta -= KEY_HEIGHT_SPEED * delta
	if height_delta == 0.0:
		return false

	_add_selected_height(height_delta)
	return true


func _is_pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _handle_left_press(screen_position: Vector2) -> void:
	var object_index: int = _find_object_at_screen_position(screen_position)
	if object_index >= 0:
		var hit_for_drag: Dictionary = _mouse_to_ground(screen_position)
		edit_mode = EditMode.SELECT
		_select_object(object_index)
		pressed_object_index = object_index
		is_dragging_selected = true
		if bool(hit_for_drag["valid"]):
			drag_offset = object_nodes[object_index].position - hit_for_drag["position"]
		else:
			drag_offset = Vector3.ZERO
		_update_status("已选中物件，拖拽平移；W/S 调整高度。")
		return

	var hit: Dictionary = _mouse_to_ground(screen_position)
	if not bool(hit["valid"]):
		return

	if edit_mode == EditMode.PLACE:
		_place_object(hit["position"])
		return

	if edit_mode == EditMode.SELECT:
		_select_object(-1)


func _handle_left_release(_screen_position: Vector2) -> void:
	if is_orbiting_camera:
		is_orbiting_camera = false
		return
	if is_dragging_selected:
		_update_status("已完成拖拽移动。")
	is_dragging_selected = false
	pressed_object_index = -1
	drag_offset = Vector3.ZERO


func _start_camera_orbit() -> void:
	is_orbiting_camera = true
	is_panning_camera = false
	is_dragging_selected = false
	pressed_object_index = -1
	drag_offset = Vector3.ZERO
	_update_status("正在旋转镜头。")


func _orbit_camera(mouse_delta: Vector2) -> void:
	camera_angle.y -= mouse_delta.x * CAMERA_ORBIT_SENSITIVITY
	camera_angle.x = clamp(
		camera_angle.x - mouse_delta.y * CAMERA_ORBIT_SENSITIVITY,
		CAMERA_MIN_PITCH,
		CAMERA_MAX_PITCH
	)
	_update_camera()


func _start_camera_pan() -> void:
	is_panning_camera = true
	is_orbiting_camera = false
	is_dragging_selected = false
	pressed_object_index = -1
	drag_offset = Vector3.ZERO
	_update_status("正在平移场景。")


func _stop_camera_pan() -> void:
	is_panning_camera = false


func _pan_camera(mouse_delta: Vector2) -> void:
	var right: Vector3 = camera.global_transform.basis.x
	var forward: Vector3 = -camera.global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized()
	forward = forward.normalized()

	var pan: Vector3 = (
		-right * mouse_delta.x +
		forward * mouse_delta.y
	) * CAMERA_PAN_SENSITIVITY * (camera_distance / 22.0)
	camera_target += pan
	var half: float = GROUND_SIZE * 0.5
	camera_target.x = clamp(camera_target.x, -half, half)
	camera_target.z = clamp(camera_target.z, -half, half)
	_update_camera()


func _drag_selected_to(position: Vector3) -> void:
	if selected_object_index < 0 or pressed_object_index != selected_object_index:
		return

	_move_selected(position + drag_offset, false)


func _mouse_to_ground(screen_position: Vector2) -> Dictionary:
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	if abs(direction.y) < 0.001:
		return {"valid": false}
	var t: float = -origin.y / direction.y
	if t < 0.0:
		return {"valid": false}
	var point: Vector3 = origin + direction * t
	var half: float = GROUND_SIZE * 0.5
	if point.x < -half or point.x > half or point.z < -half or point.z > half:
		return {"valid": false}
	return {"valid": true, "position": _apply_snap(point)}


func _apply_snap(position: Vector3) -> Vector3:
	if not snap_enabled:
		return Vector3(position.x, 0.0, position.z)
	return Vector3(
		round(position.x / snap_step) * snap_step,
		0.0,
		round(position.z / snap_step) * snap_step
	)


func _place_object(position: Vector3) -> void:
	var asset: Dictionary = _get_asset(selected_asset_id)
	if asset.is_empty():
		_update_status("放置失败：未找到模型资产。")
		return

	var object_data: Dictionary = {
		"asset_id": String(asset["id"]),
		"position": _vector_to_array(position),
		"rotation_y": brush_rotation_y,
		"scale": brush_scale
	}
	objects.append(object_data)
	_spawn_object(object_data)
	_select_object(objects.size() - 1)
	_update_status("已放置：%s。" % String(asset["name"]))


func _spawn_object(object_data: Dictionary) -> void:
	var wrapper: Node3D = _create_object_wrapper(object_data, object_nodes.size())
	object_root.add_child(wrapper)
	object_nodes.append(wrapper)


func _create_object_wrapper(object_data: Dictionary, object_index: int) -> Node3D:
	var asset: Dictionary = _get_asset(String(object_data["asset_id"]))
	var wrapper: Node3D = Node3D.new()
	wrapper.name = "Object_%s_%d" % [String(object_data["asset_id"]), object_index]
	wrapper.position = _array_to_vector(object_data["position"])
	wrapper.rotation_degrees.y = float(object_data["rotation_y"])
	wrapper.scale = Vector3.ONE * float(object_data["scale"])

	var model: Node3D = _instantiate_asset(asset)
	wrapper.add_child(model)
	_align_model_bottom_to_ground(model)
	return wrapper


func _create_export_object_wrapper(object_data: Dictionary, object_index: int) -> Node3D:
	var asset: Dictionary = _get_asset(String(object_data["asset_id"]))
	var wrapper: Node3D = Node3D.new()
	wrapper.name = "Object_%s_%d" % [String(object_data["asset_id"]), object_index]
	wrapper.position = _array_to_vector(object_data["position"])
	wrapper.rotation_degrees.y = float(object_data["rotation_y"])
	wrapper.scale = Vector3.ONE * float(object_data["scale"])
	wrapper.set_meta("asset_id", String(object_data["asset_id"]))
	wrapper.set_meta("asset_path", String(asset.get("path", "")))
	wrapper.set_meta("asset_category", String(asset.get("category", "")))

	var model: Node3D = _instantiate_asset(asset, false, true)
	wrapper.add_child(model)
	_align_model_bottom_to_ground(model)
	return wrapper


func _instantiate_asset(asset: Dictionary, apply_material_fix: bool = true, keep_instance_clean: bool = false) -> Node3D:
	if asset.is_empty():
		return _build_placeholder()

	var resource: Resource = load(String(asset["path"]))
	if resource is PackedScene:
		var scene: PackedScene = resource as PackedScene
		var instance: Node = scene.instantiate()
		if instance is Node3D:
			var model: Node3D = instance as Node3D
			if keep_instance_clean:
				model.set_meta("export_keep_instance_clean", true)
			if apply_material_fix:
				_apply_building_material_fix(model, asset)
			return model
	if resource is Mesh:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = resource as Mesh
		if apply_material_fix:
			_apply_building_material_fix(mesh_instance, asset)
		return mesh_instance

	return _build_placeholder()


func _apply_building_material_fix(model: Node3D, asset: Dictionary) -> void:
	if String(asset.get("category", "")) != "建筑":
		return

	var base_dir: String = _get_resource_directory(String(asset["path"]))
	var textures: Dictionary = _load_building_textures(base_dir)
	if textures.is_empty():
		return

	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mesh_instance: MeshInstance3D = current as MeshInstance3D
			_apply_building_materials_to_mesh(mesh_instance, textures, base_dir)
		for child in current.get_children():
			stack.append(child)


func _load_building_textures(base_dir: String) -> Dictionary:
	var textures: Dictionary = {}
	for variant in ["v1", "v2", "v3"]:
		var variant_name: String = String(variant)
		var texture_path: String = "%s/%s.png" % [base_dir, variant_name.to_upper()]
		if ResourceLoader.exists(texture_path):
			var texture: Texture2D = load(texture_path) as Texture2D
			if texture != null:
				textures[variant_name] = texture
	return textures


func _apply_building_materials_to_mesh(mesh_instance: MeshInstance3D, textures: Dictionary, base_dir: String) -> void:
	if mesh_instance.mesh == null:
		return

	var surface_count: int = mesh_instance.mesh.get_surface_count()
	for surface_index in range(surface_count):
		var variant: String = _guess_building_material_variant(mesh_instance, surface_index)
		if not textures.has(variant):
			variant = "v1"
		if not textures.has(variant):
			continue

		var texture: Texture2D = textures[variant] as Texture2D
		var material: StandardMaterial3D = _get_building_material(base_dir, variant, texture)
		mesh_instance.set_surface_override_material(surface_index, material)


func _guess_building_material_variant(mesh_instance: MeshInstance3D, surface_index: int) -> String:
	var names: Array[String] = []
	var material: Material = mesh_instance.get_active_material(surface_index)
	if material != null:
		names.append(material.resource_name.to_lower())

	if mesh_instance.mesh is ArrayMesh:
		var array_mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
		names.append(array_mesh.surface_get_name(surface_index).to_lower())

	for name in names:
		if name.contains("v3"):
			return "v3"
		if name.contains("v2"):
			return "v2"
		if name.contains("v1"):
			return "v1"
	return "v1"


func _get_building_material(base_dir: String, variant: String, texture: Texture2D) -> StandardMaterial3D:
	var cache_key: String = "%s/%s" % [base_dir, variant]
	if building_material_cache.has(cache_key):
		return building_material_cache[cache_key] as StandardMaterial3D

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "Building_%s" % variant.to_upper()
	material.resource_local_to_scene = true
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.75
	building_material_cache[cache_key] = material
	return material


func _get_resource_directory(path: String) -> String:
	var slash_index: int = path.rfind("/")
	if slash_index < 0:
		return path
	return path.substr(0, slash_index)


func _build_placeholder() -> Node3D:
	var placeholder: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.8, 0.8, 0.8)
	placeholder.mesh = mesh
	placeholder.material_override = material_placeholder
	return placeholder


func _align_model_bottom_to_ground(model: Node3D) -> void:
	var bounds: AABB = _get_local_aabb(model, model)
	if bounds.size == Vector3.ZERO:
		return
	model.position.y -= bounds.position.y


func _get_world_aabb(root: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var has_bounds: bool = false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mesh_instance: MeshInstance3D = current as MeshInstance3D
			var mesh_bounds: AABB = _transform_aabb(mesh_instance.global_transform, mesh_instance.get_aabb())
			if not has_bounds:
				bounds = mesh_bounds
				has_bounds = true
			else:
				bounds = bounds.merge(mesh_bounds)
		for child in current.get_children():
			stack.append(child)

	if not has_bounds:
		return AABB()
	return bounds


func _get_local_aabb(root: Node3D, source: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var has_bounds: bool = false
	var node_stack: Array[Node] = [source]
	var transform_stack: Array[Transform3D] = [_get_local_transform_between(root, source)]
	while not node_stack.is_empty():
		var current: Node = node_stack.pop_back()
		var current_transform: Transform3D = transform_stack.pop_back()
		if current is MeshInstance3D:
			var mesh_instance: MeshInstance3D = current as MeshInstance3D
			var mesh_bounds: AABB = _transform_aabb(current_transform, mesh_instance.get_aabb())
			if not has_bounds:
				bounds = mesh_bounds
				has_bounds = true
			else:
				bounds = bounds.merge(mesh_bounds)
		for child in current.get_children():
			var child_node: Node = child as Node
			var child_transform: Transform3D = current_transform
			if child_node is Node3D:
				var child_node_3d: Node3D = child_node as Node3D
				child_transform = current_transform * child_node_3d.transform
			node_stack.append(child_node)
			transform_stack.append(child_transform)

	if not has_bounds:
		return AABB()
	return bounds


func _get_local_transform_between(root: Node3D, node: Node3D) -> Transform3D:
	var local_transform: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			var current_3d: Node3D = current as Node3D
			local_transform = current_3d.transform * local_transform
		current = current.get_parent()
	return local_transform


func _transform_aabb(transform: Transform3D, bounds: AABB) -> AABB:
	var transformed: AABB = AABB()
	var has_point: bool = false
	for x in range(2):
		for y in range(2):
			for z in range(2):
				var corner: Vector3 = bounds.position + Vector3(
					bounds.size.x if x == 1 else 0.0,
					bounds.size.y if y == 1 else 0.0,
					bounds.size.z if z == 1 else 0.0
				)
				var point: Vector3 = transform * corner
				if not has_point:
					transformed = AABB(point, Vector3.ZERO)
					has_point = true
				else:
					transformed = transformed.expand(point)
	return transformed


func _ray_intersects_aabb(origin: Vector3, direction: Vector3, bounds: AABB) -> float:
	var t_min: float = 0.0
	var t_max: float = INF
	var min_point: Vector3 = bounds.position
	var max_point: Vector3 = bounds.position + bounds.size

	for axis in range(3):
		var ray_origin: float = origin[axis]
		var ray_direction: float = direction[axis]
		var box_min: float = min_point[axis]
		var box_max: float = max_point[axis]

		if abs(ray_direction) < 0.0001:
			if ray_origin < box_min or ray_origin > box_max:
				return -1.0
		else:
			var inv_direction: float = 1.0 / ray_direction
			var t1: float = (box_min - ray_origin) * inv_direction
			var t2: float = (box_max - ray_origin) * inv_direction
			if t1 > t2:
				var temp: float = t1
				t1 = t2
				t2 = temp
			t_min = max(t_min, t1)
			t_max = min(t_max, t2)
			if t_min > t_max:
				return -1.0

	return t_min


func _find_object_at_screen_position(screen_position: Vector2) -> int:
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var nearest: int = -1
	var nearest_distance: float = INF
	for i in range(object_nodes.size()):
		var node: Node3D = object_nodes[i]
		var bounds: AABB = _get_world_aabb(node)
		if bounds.size == Vector3.ZERO:
			continue
		var distance: float = _ray_intersects_aabb(origin, direction, bounds)
		if distance >= 0.0 and distance < nearest_distance:
			nearest = i
			nearest_distance = distance
	return nearest


func _select_object(index: int) -> void:
	selected_object_index = index
	_update_selection_marker()
	_sync_rotation_slider()
	_sync_scale_slider()
	_update_labels()


func _move_selected(position: Vector3, show_status: bool = true) -> void:
	if selected_object_index < 0 or selected_object_index >= objects.size():
		return
	var object_data: Dictionary = objects[selected_object_index]
	object_data["position"] = _vector_to_array(position)
	objects[selected_object_index] = object_data
	object_nodes[selected_object_index].position = position
	_update_selection_marker()
	if show_status:
		_update_status("已移动选中模型。")


func _add_selected_height(delta_height: float) -> void:
	if selected_object_index < 0 or selected_object_index >= objects.size():
		return

	var node: Node3D = object_nodes[selected_object_index]
	var position: Vector3 = node.position
	position.y += delta_height
	_move_selected(position, false)
	_update_labels()


func _set_current_rotation(value: float) -> void:
	var rotation_y: float = _normalize_rotation(value)
	if selected_object_index >= 0:
		var object_data: Dictionary = objects[selected_object_index]
		object_data["rotation_y"] = rotation_y
		objects[selected_object_index] = object_data
		object_nodes[selected_object_index].rotation_degrees.y = rotation_y
		_update_selection_marker()
	else:
		brush_rotation_y = rotation_y
	_update_labels()


func _add_current_rotation(delta_degrees: float) -> void:
	var rotation_y: float = brush_rotation_y
	if selected_object_index >= 0:
		var object_data: Dictionary = objects[selected_object_index]
		rotation_y = float(object_data["rotation_y"])

	_set_current_rotation(rotation_y + delta_degrees)
	_sync_rotation_slider()


func _set_current_scale(value: float) -> void:
	var scale_value: float = float(clamp(1.0 + value, MIN_SCALE, MAX_SCALE))
	if selected_object_index >= 0:
		var object_data: Dictionary = objects[selected_object_index]
		object_data["scale"] = scale_value
		objects[selected_object_index] = object_data
		object_nodes[selected_object_index].scale = Vector3.ONE * scale_value
		_update_selection_marker()
	else:
		brush_scale = scale_value
	_update_labels()


func _apply_rotation_input(text: String) -> void:
	_apply_rotation_text(text)
	if rotation_value_input != null:
		rotation_value_input.release_focus()


func _apply_rotation_text(text: String) -> void:
	if text.strip_edges().is_empty():
		_update_labels()
		return

	var value: float = _parse_number_input(text, _current_rotation())
	_set_current_rotation(value)
	_sync_rotation_slider()
	_update_labels()


func _apply_rotation_input_from_field() -> void:
	if rotation_value_input != null:
		_apply_rotation_text(rotation_value_input.text)


func _select_rotation_input_text() -> void:
	if rotation_value_input != null:
		rotation_value_input.select_all()


func _apply_scale_input(text: String) -> void:
	_apply_scale_text(text)
	if scale_value_input != null:
		scale_value_input.release_focus()


func _apply_scale_text(text: String) -> void:
	if text.strip_edges().is_empty():
		_update_labels()
		return

	var value: float = _parse_number_input(text, _current_scale())
	value = float(clamp(value, MIN_SCALE, MAX_SCALE))
	_set_current_scale(value - 1.0)
	_sync_scale_slider()
	_update_labels()


func _apply_scale_input_from_field() -> void:
	if scale_value_input != null:
		_apply_scale_text(scale_value_input.text)


func _select_scale_input_text() -> void:
	if scale_value_input != null:
		scale_value_input.select_all()


func _add_current_scale(delta_scale: float) -> void:
	var scale_value: float = brush_scale
	if selected_object_index >= 0:
		var object_data: Dictionary = objects[selected_object_index]
		scale_value = float(object_data["scale"])

	scale_value = float(clamp(scale_value + delta_scale, MIN_SCALE, MAX_SCALE))
	_set_current_scale(scale_value - 1.0)
	_sync_scale_slider()


func _reset_selected_transform() -> void:
	if selected_object_index < 0 or selected_object_index >= objects.size():
		brush_rotation_y = 0.0
		brush_scale = 1.0
		_sync_rotation_slider()
		_sync_scale_slider()
		_update_labels()
		_update_status("已重置画笔旋转和缩放。")
		return

	var object_data: Dictionary = objects[selected_object_index]
	object_data["rotation_y"] = 0.0
	object_data["scale"] = 1.0
	objects[selected_object_index] = object_data
	object_nodes[selected_object_index].rotation_degrees.y = 0.0
	object_nodes[selected_object_index].scale = Vector3.ONE
	_update_selection_marker()
	_sync_rotation_slider()
	_sync_scale_slider()
	_update_labels()
	_update_status("已重置选中物件的旋转和缩放。")


func _delete_selected() -> void:
	if selected_object_index < 0 or selected_object_index >= objects.size():
		_update_status("没有选中模型。")
		return

	var removed_node: Node3D = object_nodes[selected_object_index]
	removed_node.queue_free()
	objects.remove_at(selected_object_index)
	object_nodes.remove_at(selected_object_index)
	_select_object(-1)
	_update_status("已删除选中模型。")


func _copy_selected() -> void:
	if selected_object_index < 0 or selected_object_index >= objects.size():
		_update_status("没有选中模型。")
		return

	copied_object_data = objects[selected_object_index].duplicate(true)
	_update_status("已复制选中模型，可点击粘贴或按 Ctrl+V。")


func _paste_copied() -> void:
	if copied_object_data.is_empty():
		_update_status("还没有复制模型。")
		return

	var source: Dictionary = copied_object_data.duplicate(true)
	var position: Vector3 = _array_to_vector(source["position"]) + Vector3(1.0, 0.0, 1.0)
	var snapped_position: Vector3 = _apply_snap(position)
	snapped_position.y = position.y
	source["position"] = _vector_to_array(snapped_position)
	objects.append(source)
	_spawn_object(source)
	_select_object(objects.size() - 1)
	_update_status("已粘贴模型。")


func _duplicate_selected() -> void:
	if selected_object_index < 0 or selected_object_index >= objects.size():
		_update_status("没有选中模型。")
		return
	copied_object_data = objects[selected_object_index].duplicate(true)
	_paste_copied()


func _save_level() -> void:
	var payload: Dictionary = _build_scene_payload()
	if _write_json_payload(SAVE_PATH, payload):
		_update_status("已保存：%d 个模型，包含镜头缩放和朝向。" % objects.size())


func _export_scene() -> void:
	var payload: Dictionary = _build_scene_payload()
	if not _write_json_payload(SAVE_PATH, payload):
		return
	var scene_path: String = _next_export_scene_path()
	if scene_path.is_empty():
		return
	if _write_tscn_scene(scene_path):
		var export_path: String = ProjectSettings.globalize_path(scene_path)
		_update_status("已保存并导出 TSCN 场景：%s" % export_path)


func _next_export_scene_path() -> String:
	var export_dir_absolute: String = ProjectSettings.globalize_path(EXPORT_SCENE_DIR)
	if not DirAccess.dir_exists_absolute(export_dir_absolute):
		var dir_error: int = DirAccess.make_dir_recursive_absolute(export_dir_absolute)
		if dir_error != OK:
			_update_status("导出失败：创建导出目录失败 %s。" % error_string(dir_error))
			return ""

	var dir: DirAccess = DirAccess.open(export_dir_absolute)
	if dir == null:
		_update_status("导出失败：打开导出目录失败 %s。" % error_string(DirAccess.get_open_error()))
		return ""

	var highest_index: int = 0
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var export_index: int = _export_index_from_file_name(file_name)
			if export_index > highest_index:
				highest_index = export_index
		file_name = dir.get_next()
	dir.list_dir_end()

	return "%s/%s_%03d.tscn" % [EXPORT_SCENE_DIR, EXPORT_SCENE_BASENAME, highest_index + 1]


func _export_index_from_file_name(file_name: String) -> int:
	var prefix: String = "%s_" % EXPORT_SCENE_BASENAME
	var suffix: String = ".tscn"
	if not file_name.begins_with(prefix) or not file_name.ends_with(suffix):
		return 0

	var index_text: String = file_name.substr(prefix.length(), file_name.length() - prefix.length() - suffix.length())
	if index_text.is_empty():
		return 0

	for i in range(index_text.length()):
		var codepoint: int = index_text.unicode_at(i)
		if codepoint < 48 or codepoint > 57:
			return 0

	return int(index_text)


func _write_tscn_scene(path: String) -> bool:
	var scene_root: Node3D = _build_export_scene_root()
	var packed_scene: PackedScene = PackedScene.new()
	var pack_error: int = packed_scene.pack(scene_root)
	if pack_error != OK:
		scene_root.free()
		_update_status("导出失败：打包场景失败 %s。" % error_string(pack_error))
		return false

	var save_error: int = ResourceSaver.save(packed_scene, path)
	scene_root.free()
	if save_error != OK:
		_update_status("导出失败：写入 TSCN 失败 %s。" % error_string(save_error))
		return false
	return true


func _build_export_scene_root() -> Node3D:
	var scene_root: Node3D = Node3D.new()
	scene_root.name = "ExportedLevel"
	var runtime_script: Script = load(EXPORT_RUNTIME_SCRIPT_PATH) as Script
	if runtime_script != null:
		scene_root.set_script(runtime_script)
	scene_root.set_meta("editor_camera_distance", camera_distance)
	scene_root.set_meta("editor_camera_target", camera_target)
	scene_root.set_meta("editor_camera_pitch", camera_angle.x)
	scene_root.set_meta("editor_camera_yaw", camera_angle.y)

	var light: DirectionalLight3D = _create_scene_light()
	scene_root.add_child(light)

	var ambient: WorldEnvironment = _create_scene_environment()
	scene_root.add_child(ambient)

	var ground: MeshInstance3D = _create_scene_ground()
	scene_root.add_child(ground)

	var export_camera: Camera3D = Camera3D.new()
	export_camera.name = "Camera3D"
	export_camera.transform = camera.transform
	export_camera.current = true
	scene_root.add_child(export_camera)

	var exported_objects: Node3D = Node3D.new()
	exported_objects.name = "Objects"
	scene_root.add_child(exported_objects)
	for i in range(objects.size()):
		var object_data: Dictionary = objects[i]
		var wrapper: Node3D = _create_export_object_wrapper(object_data, i)
		exported_objects.add_child(wrapper)

	_assign_scene_owner(scene_root, scene_root)
	return scene_root


func _assign_scene_owner(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		var child_node: Node = child as Node
		child_node.owner = scene_root
		if child_node.has_meta("export_keep_instance_clean"):
			continue
		_assign_scene_owner(child_node, scene_root)


func _build_scene_payload() -> Dictionary:
	return {
		"version": 2,
		"mode": "free_model_editor",
		"camera": _get_camera_data(),
		"objects": objects
	}


func _get_camera_data() -> Dictionary:
	return {
		"distance": camera_distance,
		"zoom": camera_distance,
		"target": _vector_to_array(camera_target),
		"orientation": {
			"pitch": camera_angle.x,
			"yaw": camera_angle.y,
			"pitch_degrees": rad_to_deg(camera_angle.x),
			"yaw_degrees": rad_to_deg(camera_angle.y)
		}
	}


func _write_json_payload(path: String, payload: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://levels"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_update_status("写入失败：%s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func _load_level() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_update_status("加载失败：还没有保存文件。")
		return

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_update_status("加载失败：%s" % error_string(FileAccess.get_open_error()))
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		_update_status("加载失败：关卡文件格式不正确。")
		return

	var data: Dictionary = parsed
	if not data.has("objects"):
		_update_status("加载失败：缺少 objects 数据。")
		return

	_clear_scene_objects()
	var loaded_objects: Array = data["objects"]
	for item in loaded_objects:
		var object_data: Dictionary = item
		objects.append(object_data)
		_spawn_object(object_data)
	if data.has("camera") and typeof(data["camera"]) == TYPE_DICTIONARY:
		var camera_data: Dictionary = data["camera"]
		_apply_camera_data(camera_data)
	_select_object(-1)
	_update_status("已加载：%d 个模型。" % objects.size())


func _load_saved_level_on_startup() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_load_level()


func _apply_camera_data(camera_data: Dictionary) -> void:
	var distance_value: float = camera_distance
	if camera_data.has("distance"):
		distance_value = float(camera_data["distance"])
	elif camera_data.has("zoom"):
		distance_value = float(camera_data["zoom"])
	camera_distance = float(clamp(distance_value, CAMERA_MIN_DISTANCE, CAMERA_MAX_DISTANCE))

	if camera_data.has("target"):
		camera_target = _array_to_vector(camera_data["target"])

	if camera_data.has("orientation") and typeof(camera_data["orientation"]) == TYPE_DICTIONARY:
		var orientation: Dictionary = camera_data["orientation"]
		if orientation.has("pitch"):
			camera_angle.x = float(orientation["pitch"])
		if orientation.has("yaw"):
			camera_angle.y = float(orientation["yaw"])
	elif camera_data.has("angle") and typeof(camera_data["angle"]) == TYPE_ARRAY:
		var angle: Array = camera_data["angle"]
		if angle.size() >= 2:
			camera_angle.x = float(angle[0])
			camera_angle.y = float(angle[1])

	camera_angle.x = float(clamp(camera_angle.x, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH))
	_update_camera()


func _clear_level() -> void:
	_clear_scene_objects()
	_update_status("已清空当前关卡。")


func _clear_scene_objects() -> void:
	for node in object_nodes:
		node.queue_free()
	object_nodes.clear()
	objects.clear()
	_select_object(-1)


func _build_sample_level() -> void:
	_clear_scene_objects()
	var terrain_id: String = _sample_asset_id(["地形", "雪地地形", "基础"])
	var tree_id: String = _sample_asset_id(["树木", "雪地树木", "基础"])
	var rock_id: String = _sample_asset_id(["岩石", "雪地岩石", "基础"])
	var plant_id: String = _sample_asset_id(["植物", "基础"])
	var wood_id: String = _sample_asset_id(["木件", "基础"])
	var sample: Array[Dictionary] = []
	_append_sample_object(sample, terrain_id, Vector3(0.0, 0.0, 0.0), 0.0, 1.8)
	_append_sample_object(sample, tree_id, Vector3(-4.0, 0.0, -3.0), 20.0, 1.2)
	_append_sample_object(sample, tree_id, Vector3(-2.2, 0.0, -4.0), -15.0, 1.0)
	_append_sample_object(sample, rock_id, Vector3(2.0, 0.0, -1.5), 55.0, 1.0)
	_append_sample_object(sample, plant_id, Vector3(-1.5, 0.0, 2.8), 0.0, 1.0)
	_append_sample_object(sample, wood_id, Vector3(0.5, 0.0, 3.5), 70.0, 1.1)
	for item in sample:
		var object_data: Dictionary = item
		objects.append(object_data)
		_spawn_object(object_data)
	_select_object(-1)
	_update_status("已生成自由摆放示例。")


func _append_sample_object(target: Array[Dictionary], asset_id: String, position: Vector3, rotation_y: float, scale: float) -> void:
	if asset_id.is_empty():
		return
	target.append({
		"asset_id": asset_id,
		"position": _vector_to_array(position),
		"rotation_y": rotation_y,
		"scale": scale
	})


func _sample_asset_id(categories: Array) -> String:
	for category in categories:
		var asset: Dictionary = _find_first_asset_in_category(category)
		if not asset.is_empty():
			return String(asset["id"])
	if not asset_catalog.is_empty():
		return String(asset_catalog[0]["id"])
	return ""


func _set_mode(mode: int) -> void:
	edit_mode = mode
	_update_labels()


func _select_asset(asset_id: String) -> void:
	selected_asset_id = asset_id
	var asset: Dictionary = _get_asset(asset_id)
	if not asset.is_empty():
		brush_scale = float(asset["scale"])
	edit_mode = EditMode.PLACE
	_select_object(-1)
	_update_labels()


func _toggle_snap() -> void:
	snap_enabled = not snap_enabled
	_update_labels()


func _load_asset_catalog() -> void:
	asset_catalog.clear()
	asset_categories.clear()

	if FileAccess.file_exists(ASSET_CATALOG_PATH):
		var file: FileAccess = FileAccess.open(ASSET_CATALOG_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				var catalog_data: Dictionary = parsed
				if catalog_data.has("assets") and typeof(catalog_data["assets"]) == TYPE_ARRAY:
					var parsed_assets: Array = catalog_data["assets"]
					for item in parsed_assets:
						var asset_data: Dictionary = item
						asset_catalog.append(asset_data)

	for asset in FALLBACK_ASSETS:
		var fallback_asset: Dictionary = asset
		if _asset_id_exists(String(fallback_asset["id"])):
			continue
		var copy: Dictionary = fallback_asset.duplicate(true)
		copy["category"] = "基础"
		asset_catalog.append(copy)

	for asset in asset_catalog:
		var asset_data: Dictionary = asset
		var category: String = String(asset_data.get("category", "其他"))
		if not asset_categories.has(category):
			asset_categories.append(category)
	asset_categories.sort()

	if not asset_categories.is_empty():
		selected_category = asset_categories[0]
		var first_asset: Dictionary = _find_first_asset_in_category(selected_category)
		if not first_asset.is_empty():
			selected_asset_id = String(first_asset["id"])


func _refresh_category_filter() -> void:
	if category_filter == null:
		return

	category_filter.clear()
	for category in asset_categories:
		category_filter.add_item(category)
		if category == selected_category:
			category_filter.select(category_filter.get_item_count() - 1)
	_refresh_asset_list()


func _refresh_asset_list() -> void:
	if asset_list == null:
		return

	asset_list.clear()
	var selected_index: int = -1
	for asset in asset_catalog:
		var asset_data: Dictionary = asset
		if String(asset_data.get("category", "其他")) != selected_category:
			continue
		asset_list.add_item(String(asset_data["name"]))
		var index: int = asset_list.get_item_count() - 1
		asset_list.set_item_metadata(index, String(asset_data["id"]))
		if String(asset_data["id"]) == selected_asset_id:
			selected_index = index

	if selected_index < 0 and asset_list.get_item_count() > 0:
		selected_index = 0
		selected_asset_id = String(asset_list.get_item_metadata(0))

	if selected_index >= 0:
		asset_list.select(selected_index)
	_update_labels()


func _select_category_by_index(index: int) -> void:
	if index < 0 or index >= asset_categories.size():
		return
	selected_category = asset_categories[index]
	var first_asset: Dictionary = _find_first_asset_in_category(selected_category)
	if not first_asset.is_empty():
		selected_asset_id = String(first_asset["id"])
	edit_mode = EditMode.PLACE
	_select_object(-1)
	_refresh_asset_list()


func _select_asset_by_index(index: int) -> void:
	if asset_list == null or index < 0 or index >= asset_list.get_item_count():
		return
	_select_asset(String(asset_list.get_item_metadata(index)))


func _find_first_asset_in_category(category: String) -> Dictionary:
	for asset in asset_catalog:
		var asset_data: Dictionary = asset
		if String(asset_data.get("category", "其他")) == category:
			return asset_data
	return {}


func _asset_id_exists(asset_id: String) -> bool:
	for asset in asset_catalog:
		var asset_data: Dictionary = asset
		if String(asset_data["id"]) == asset_id:
			return true
	return false


func _get_asset(asset_id: String) -> Dictionary:
	for asset in asset_catalog:
		var asset_data: Dictionary = asset
		if String(asset_data["id"]) == asset_id:
			return asset_data
	return {}


func _array_to_vector(value: Variant) -> Vector3:
	var array: Array = value
	return Vector3(float(array[0]), float(array[1]), float(array[2]))


func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _update_camera() -> void:
	var pitch: float = camera_angle.x
	var yaw: float = camera_angle.y
	var direction: Vector3 = Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	)
	camera.position = camera_target - direction * camera_distance
	camera.look_at(camera_target, Vector3.UP)


func _update_selection_marker() -> void:
	if selected_object_index < 0 or selected_object_index >= object_nodes.size():
		selection_marker.visible = false
		return

	var node: Node3D = object_nodes[selected_object_index]
	selection_marker.visible = true
	selection_marker.position = Vector3(node.position.x, node.position.y + 0.04, node.position.z)
	selection_marker.scale = Vector3.ONE * max(0.8, node.scale.x)


func _update_labels() -> void:
	if mode_label == null:
		return

	var mode_text: String = "放置" if edit_mode == EditMode.PLACE else "选择/移动"
	mode_label.text = "模式：%s  吸附：%s" % [mode_text, "开" if snap_enabled else "关"]

	var asset: Dictionary = _get_asset(selected_asset_id)
	asset_label.text = "当前模型：%s" % String(asset["name"] if not asset.is_empty() else selected_asset_id)

	if selected_object_index >= 0 and selected_object_index < objects.size():
		var object_data: Dictionary = objects[selected_object_index]
		if rotation_value_input != null and not rotation_value_input.has_focus():
			rotation_value_input.text = "%.0f°" % float(object_data["rotation_y"])
		if scale_value_input != null and not scale_value_input.has_focus():
			scale_value_input.text = "%.2fx" % float(object_data["scale"])
		var position: Vector3 = _array_to_vector(object_data["position"])
		transform_label.text = "选中：%s  高度 %.2f  旋转 %.0f°  缩放 %.2f" % [
			String(object_data["asset_id"]),
			position.y,
			float(object_data["rotation_y"]),
			float(object_data["scale"])
		]
	else:
		if rotation_value_input != null and not rotation_value_input.has_focus():
			rotation_value_input.text = "%.0f°" % brush_rotation_y
		if scale_value_input != null and not scale_value_input.has_focus():
			scale_value_input.text = "%.2fx" % brush_scale
		transform_label.text = "画笔：旋转 %.0f°  缩放 %.2f" % [brush_rotation_y, brush_scale]


func _current_rotation() -> float:
	if selected_object_index >= 0 and selected_object_index < objects.size():
		var object_data: Dictionary = objects[selected_object_index]
		return float(object_data["rotation_y"])
	return brush_rotation_y


func _current_scale() -> float:
	if selected_object_index >= 0 and selected_object_index < objects.size():
		var object_data: Dictionary = objects[selected_object_index]
		return float(object_data["scale"])
	return brush_scale


func _parse_number_input(text: String, fallback: float) -> float:
	var cleaned: String = text.strip_edges()
	cleaned = cleaned.replace("°", "")
	cleaned = cleaned.replace("x", "")
	cleaned = cleaned.replace("X", "")
	cleaned = cleaned.replace("倍", "")
	cleaned = cleaned.replace(",", ".")
	cleaned = cleaned.strip_edges()
	if not cleaned.is_valid_float():
		_update_status("输入无效，已保留原值。")
		return fallback
	return cleaned.to_float()


func _sync_rotation_slider() -> void:
	if rotation_slider == null:
		return

	var rotation_y: float = brush_rotation_y
	if selected_object_index >= 0 and selected_object_index < objects.size():
		var object_data: Dictionary = objects[selected_object_index]
		rotation_y = float(object_data["rotation_y"])

	rotation_slider.set_value_no_signal(_normalize_rotation(rotation_y))


func _sync_scale_slider() -> void:
	if scale_slider == null:
		return

	var scale_value: float = brush_scale
	if selected_object_index >= 0 and selected_object_index < objects.size():
		var object_data: Dictionary = objects[selected_object_index]
		scale_value = float(object_data["scale"])

	scale_slider.set_value_no_signal(float(clamp(scale_value - 1.0, SLIDER_MIN, SLIDER_MAX)))


func _normalize_rotation(value: float) -> float:
	var rotation_y: float = fmod(value, 360.0)
	if rotation_y > 180.0:
		rotation_y -= 360.0
	elif rotation_y < -180.0:
		rotation_y += 360.0
	return rotation_y


func _update_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
