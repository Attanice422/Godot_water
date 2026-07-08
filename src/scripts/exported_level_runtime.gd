extends Node3D

const DEFAULT_CAMERA_DISTANCE := 22.0

var material_cache: Dictionary = {}


func _ready() -> void:
	_apply_exported_camera()
	_apply_exported_materials()


func _apply_exported_camera() -> void:
	var camera_node: Node = get_node_or_null("Camera3D")
	if not (camera_node is Camera3D):
		return

	var camera: Camera3D = camera_node as Camera3D
	var distance: float = float(get_meta("editor_camera_distance", DEFAULT_CAMERA_DISTANCE))
	var target: Vector3 = Vector3.ZERO
	var target_value: Variant = get_meta("editor_camera_target", Vector3.ZERO)
	if typeof(target_value) == TYPE_VECTOR3:
		target = target_value

	var pitch: float = float(get_meta("editor_camera_pitch", deg_to_rad(-48.0)))
	var yaw: float = float(get_meta("editor_camera_yaw", deg_to_rad(45.0)))
	var direction: Vector3 = Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	).normalized()

	camera.position = target - direction * distance
	if camera.position.distance_squared_to(target) > 0.0001:
		camera.look_at(target, Vector3.UP)
	camera.current = true


func _apply_exported_materials() -> void:
	var objects_node: Node = get_node_or_null("Objects")
	if objects_node == null:
		return

	for child in objects_node.get_children():
		var wrapper: Node = child as Node
		var asset_path: String = String(wrapper.get_meta("asset_path", ""))
		if asset_path.is_empty():
			continue

		var model: Node3D = _first_node3d_child(wrapper)
		if model == null:
			continue

		_apply_material_fix(model, asset_path)


func _first_node3d_child(node: Node) -> Node3D:
	for child in node.get_children():
		if child is Node3D:
			return child as Node3D
	return null


func _apply_material_fix(model: Node3D, asset_path: String) -> void:
	var base_dir: String = _get_resource_directory(asset_path)
	var textures: Dictionary = _load_textures(base_dir)
	if textures.is_empty():
		return

	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mesh_instance: MeshInstance3D = current as MeshInstance3D
			_apply_materials_to_mesh(mesh_instance, textures, base_dir)
		for child in current.get_children():
			stack.append(child)


func _load_textures(base_dir: String) -> Dictionary:
	var textures: Dictionary = {}
	var variants: Array[String] = ["v1", "v2", "v3"]
	for variant in variants:
		var texture_path: String = "%s/%s.png" % [base_dir, variant.to_upper()]
		if ResourceLoader.exists(texture_path):
			var texture: Texture2D = load(texture_path) as Texture2D
			if texture != null:
				textures[variant] = texture
	return textures


func _apply_materials_to_mesh(mesh_instance: MeshInstance3D, textures: Dictionary, base_dir: String) -> void:
	if mesh_instance.mesh == null:
		return

	var surface_count: int = mesh_instance.mesh.get_surface_count()
	for surface_index in range(surface_count):
		var variant: String = _guess_material_variant(mesh_instance, surface_index)
		if not textures.has(variant):
			variant = "v1"
		if not textures.has(variant):
			continue

		var texture: Texture2D = textures[variant] as Texture2D
		var material: StandardMaterial3D = _get_material(base_dir, variant, texture)
		mesh_instance.set_surface_override_material(surface_index, material)


func _guess_material_variant(mesh_instance: MeshInstance3D, surface_index: int) -> String:
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


func _get_material(base_dir: String, variant: String, texture: Texture2D) -> StandardMaterial3D:
	var cache_key: String = "%s/%s" % [base_dir, variant]
	if material_cache.has(cache_key):
		return material_cache[cache_key] as StandardMaterial3D

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "Building_%s" % variant.to_upper()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.75
	material_cache[cache_key] = material
	return material


func _get_resource_directory(path: String) -> String:
	var slash_index: int = path.rfind("/")
	if slash_index < 0:
		return path
	return path.substr(0, slash_index)
