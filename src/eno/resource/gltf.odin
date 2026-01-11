package resource

import "vendor:cgltf"

import "../utils"
import dbg "../debug"
import "../standards"
import futils "../file_utils"

import "core:testing"
import "core:strings"

DEFAULT_OPTIONS: cgltf.options
load_gltf :: proc(path: string) -> (data: ^cgltf.data, result: cgltf.result) {
    result = .io_error

    dbg.log(.INFO, "Reading gltf file. Path: \"%s\"", path)

    cpath := strings.clone_to_cstring(path)

    data, result = cgltf.parse_file(DEFAULT_OPTIONS, cpath)

    if result != .success {
        dbg.log(.ERROR, "Unable to load gltf file. Path: \"%s\"", path)
        return
    }
    if result = cgltf.load_buffers(DEFAULT_OPTIONS, data, cpath); result != .success {
        dbg.log(.ERROR, "Unable to load default buffers for gltf scenes. Path: \"%s\"", path)
        return
    }
    if result = cgltf.validate(data); result != .success {
        dbg.log(.ERROR, "Unable to validate imported data for gltf scenes. Path: \"%s\"", path)
        return
    }

    return data, .success
}


@(test)
load_model_test :: proc(t: ^testing.T) {
    data, result := load_gltf("SciFiHelmet")
    defer cgltf.free(data)

    testing.expect_value(t, result, cgltf.result.success)
    testing.expect(t, data != nil, "nil check")
}


ModelWorldPair :: struct {
    model: Model,
    world_comp: standards.WorldComponent
}

ModelSceneResult :: struct {
    models: [dynamic]ModelWorldPair,
    point_lights: [dynamic]PointLight,
    spot_lights: [dynamic]SpotLight,
    directional_lights: [dynamic]DirectionalLight
}

init_model_scene_result :: proc() -> ModelSceneResult {
    return { make([dynamic]ModelWorldPair), make([dynamic]PointLight), make([dynamic]SpotLight), make([dynamic]DirectionalLight) }
}

destroy_model_scene_result :: proc(result: ModelSceneResult) {
    delete(result.models)
    delete(result.point_lights)
    delete(result.spot_lights)
    delete(result.directional_lights)
}


extract_gltf_scene :: proc{ extract_gltf_scene_from_path, extract_gltf_scene_no_path }

extract_gltf_scene_from_path :: proc(manager: ^ResourceManager, path: string, scene_index := -1) -> (result: ModelSceneResult, ok: bool) {
    futils.check_path(path) or_return
    gltf_folder_path, path_ok := futils.file_path_to_folder_path(path)
    if !path_ok {
        dbg.log(.ERROR, "Given path does not represent a file")
        return
    }

    data, res := load_gltf(path)
    if res != .success do return

    return extract_gltf_scene_no_path(manager, data, gltf_folder_path, scene_index)
}

extract_gltf_scene_no_path :: proc(manager: ^ResourceManager, data: ^cgltf.data, gltf_folder_path: string, scene_index := -1) -> (result: ModelSceneResult, ok: bool) {
    scene: ^cgltf.scene
    if scene_index == -1 do scene = data.scene
    else {
        if scene_index < 0 || scene_index >= len(data.scenes) {
            dbg.log(.ERROR, "scene_index is out of range of gltf scenes")
            return
        }
        scene = &data.scenes[scene_index]
    }
    result = init_model_scene_result()

    node_loop: for node in scene.nodes {
        pairs := extract_node(manager, node, gltf_folder_path) or_return
        defer delete(pairs)
        append(&result.models, ..pairs)
    }

    ok = true
    return
}


extract_node :: proc(
    manager: ^ResourceManager,
    node: ^cgltf.node,
    gltf_folder_path: string,
    parent_world_comp: Maybe(standards.WorldComponent) = nil,
    allocator := context.allocator
) -> (result: []ModelWorldPair, ok: bool) {
    world_comp := standards.make_world_component()
    result_dyn := make([dynamic]ModelWorldPair, allocator=allocator)

    if node == nil do return result, true

    // dbg.log(.INFO, "Extracting node: %#v", node)

    // todo matrix/TRS vectors here are relative to parent.

    /*
    if node.has_matrix {
        model_arr := node.matrix_
        model_mat := utils.arr_to_matrix(matrix[4, 4]f32, model_arr)
        world_comp.position, world_comp.scale, world_comp.rotation = utils.decompose_transform(model_mat)
        cgltf.node_transform_local()
    }
    else {
        if node.has_translation do world_comp.position = node.translation
        if node.has_rotation do world_comp.rotation = quaternion(x=node.rotation[0], y=node.rotation[1], z=node.rotation[2], w=node.rotation[3])
        if node.has_scale do world_comp.scale = node.scale
        else do world_comp.scale = [3]f32{ 1.0, 1.0, 1.0 }
    }
    */
    // if parent_world_comp != nil do world_comp = utils.combine_world_components(parent_world_comp.?, world_comp)


    transform: matrix[4, 4]f32
    cgltf.node_transform_world(node, raw_data(&transform))
    // world_comp.position, world_comp.scale, world_comp.rotation = utils.decompose_transform(transform)
    world_comp = standards.make_world_component(transformation=transform)

    dbg.log(.INFO, "Extracting gltf node with transform: %#v", world_comp.transformation.?)

    if node.mesh != nil {
        model := extract_cgltf_mesh(manager, node.mesh^, gltf_folder_path) or_return
        dbg.log(.INFO, "Extracted model/cgltf mesh: %#v", model.name)
        append(&result_dyn, ModelWorldPair{ model, world_comp })
    }

    // Todo add recursion limit
    for child in node.children {
        new_model_pairs := extract_node(manager, child, gltf_folder_path, world_comp, allocator=allocator) or_return
        defer delete(new_model_pairs, allocator=allocator)
        append_elems(&result_dyn, ..new_model_pairs)
    }

    return result_dyn[:], true
/* for KHR_lights_punctual - not intending to really support right now, can rework this later if needed
else if node.light != nil {
    switch node.light.type {
        case .invalid:
            dbg.debug_point(.WARN, "Invalid light type found, ignoring")
            continue node_loop
        case .point:
            light := LightSourceInformation{
                strings.clone_from_cstring(node.light.name),
                true,
                node.light.intensity,
                [4]f32{ node.light.color.x, node.light.color.y, node.light.color.z, 1.0 },
                world_comp.position
            }
            if node.light.type == .point do append(&result.point_lights, light)
            else do append(&result.directional_lights, light)
        case .directional:
            light := LightSourceInformation{
                strings.clone_from_cstring(node.light.name),
                true,
                node.light.intensity,
                [4]f32{ node.light.color.x, node.light.color.y, node.light.color.z, 1.0 },
                world_comp.position
            }

        case .spot:
            spot_light := SpotLight {
                {
                    strings.clone_from_cstring(node.light.name),
                    true,
                    node.light.intensity,
                    [4]f32{ node.light.color.x, node.light.color.y, node.light.color.z, 1.0 },
                    world_comp.position
                },
                node.light.spot_inner_cone_angle,
                node.light.spot_outer_cone_angle
            }
            append(&result.spot_lights, spot_light)
    }
}
*/
}


extract_model :: proc(manager: ^ResourceManager, path: string, model_name: string) -> (model: Model, ok: bool) {
    futils.check_path(path) or_return
    gltf_folder_path, path_ok := futils.file_path_to_folder_path(path)
    if !path_ok {
        dbg.log(.ERROR, "Given path does not represent a file")
        return
    }

    data, res := load_gltf(path)
    if res != .success do return


    for mesh in data.meshes {
        if strings.compare(string(mesh.name), model_name) == 0 do return extract_cgltf_mesh(manager, mesh, gltf_folder_path)
    }

    ok = false
    return
}

/*
    Gives an eno mesh for each primitive in the cgltf "mesh"
    todo add allocator options
*/
extract_cgltf_mesh :: proc(manager: ^ResourceManager, mesh: cgltf.mesh, gltf_file_location: string) -> (model: Model, ok: bool) {
    //This is assuming all mesh attributes (aside from indices) have the same count (for each primitive/mesh output)
    meshes := make([dynamic]Mesh, len(mesh.primitives))

    dbg.log(.INFO, "Extracting mesh of name: '%s'", mesh.name)
    dbg.log(.INFO, "Mesh has n: %d primitives", len(mesh.primitives))

    for primitive, i in mesh.primitives {
        mesh_ret := &meshes[i]

        // Set material properties
        if primitive.material != nil {
            mesh_ret.material = eno_material_from_cgltf_material(manager, primitive.material^, gltf_file_location) or_return
        }
        dbg.log(.INFO, "Loading primitive of type '%v'", primitive.type)

        // Order attributes in NORMAL, POSITION, TANGENT, TEXCOORD
        // Do not allow attributes outside these types
        attributes := make([dynamic]^cgltf.attribute)
        allowed_types := []MeshAttributeType{ .normal, .position, .tangent, .texcoord }
        for type in allowed_types {
            for &attribute in primitive.attributes do if cast(MeshAttributeType)int(attribute.type) == type {
                append(&attributes, &attribute)
            }
        }
        if len(attributes) != len(primitive.attributes) do dbg.log(.WARN, "Certain attributes in the mesh %s were not loaded", mesh.name)

        // Construct layout
        layout: VertexLayout
        layout.infos = make([]MeshAttributeInfo, len(primitive.attributes))
        for attribute, i in attributes {
            accessor := attribute.data

            attribute_type := cast(MeshAttributeType)int(attribute.type)
            element_type := cast(MeshElementType)int(accessor.type)
            attribute_info := MeshAttributeInfo{
                attribute_type,
                element_type,
                get_size_of_element_type(element_type) or_return,
                string(attribute.name)
            }
            layout.infos[i] = attribute_info
        }
        layout_id := add_vertex_layout(manager, layout) or_return
        mesh_ret.layout = layout_id


        mesh_ret.vertex_data = extract_vertex_data_from_primitive(attributes[:], layout.infos) or_return
        mesh_ret.vertices_count = len(mesh_ret.vertex_data)
        mesh_ret.index_data = extract_index_data_from_primitive(primitive) or_return
        mesh_ret.indices_count = len(mesh_ret.index_data)

        mesh_ret.centroid = calculate_centroid(mesh_ret.vertex_data, layout.infos) or_return
    }

    ok = true
    model = { strings.clone_from_cstring(mesh.name), meshes }
    return
}


extract_vertex_data_from_primitive :: proc(attributes: []^cgltf.attribute, attribute_infos: []MeshAttributeInfo) -> (result: VertexData, ok: bool) {

    if len(attributes) == 0 {
        dbg.log(.ERROR, "Primitive must have attributes")
        return
    }
    if len(attributes) != len(attribute_infos) {
        dbg.log(.ERROR, "Number of primitive attributes does not match the attribute infos given")
        return
    }

    stride: uint
    for info in attribute_infos do stride += info.size_in_bytes
    float_stride : uint = stride >> 2

    count := attributes[0].data.count
    result = make(VertexData, float_stride * count)

    element_offset: uint = 0
    for attribute, i in attributes {
        accessor := attribute.data

        n_floats_in_element := attribute_infos[i].size_in_bytes >> 2

        vertex_offset: uint = 0
        for j in 0..<count {

            read_res: b32 = cgltf.accessor_read_float(accessor, j, &result[vertex_offset + element_offset], n_floats_in_element)
            if read_res == false {
                dbg.log(.ERROR, "Error while reading float from accessor, received boolean false")
                return
            }

            vertex_offset += float_stride
        }
        element_offset += n_floats_in_element
    }

    ok = true
    return
}

@(private)
extract_index_data_from_primitive :: proc(primitive: cgltf.primitive) -> (result: IndexData, ok: bool) {
    accessor := primitive.indices
    result = make(IndexData)

    utils.append_n(&result, u32(accessor.count))
    for k in 0..<accessor.count {
        raw_index_data: [^]u32 = raw_data(result[k:k+1])
        read_res: b32 = cgltf.accessor_read_uint(accessor, k, raw_index_data, 1)
        if read_res == false {
            dbg.log(.ERROR, "Error while reading uint(index) from accessor, received boolean false")
            return
        }

    }

    ok = true
    return
}

//Returns in bytes
@(private)
get_size_of_element_type :: proc(element_type: MeshElementType) -> (size: uint, ok: bool) {
    switch element_type {
        case .invalid:
            dbg.log(.INFO, "Invalid element type found")
            return
        case .scalar: size = 4
        case .vec2: size = 8
        case .vec3: size = 12
        case .vec4: size = 16
        case .mat2: size = 16
        case .mat3: size = 36
        case .mat4: size = 64
    }

    ok = true
    return
}


/*
@(test)
extract_vertex_data_test :: proc(t: ^testing.T) {
    data, result := load_gltf_mesh_primitives("SciFiHelmet")
    defer cgltf.free(data)

    //Expected usage is defined here.
    //destroy_mesh does not clean up the vertex_layout, so you must do it yourself if you allocate a VertexLayout


    res, ok := extract_model(data.meshes[0])
    defer for &mesh in res.meshes do destroy_mesh(&mesh)

    testing.expect(t, ok, "ok check")
    testing.expect_value(t, 70074, len(res.meshes[0].vertex_data) / 12)
    log.infof("meshes size: %d, mesh components: %#v, len mesh vertices: %d", len(res.meshes), res.meshes[0].layout, len(res.meshes[0].vertex_data) / 12)
}


@(test)
extract_index_data_test :: proc(t: ^testing.T) {
    data, result := load_gltf_mesh_primitives("SciFiHelmet")

    res, ok := extract_index_data_from_mesh(data.meshes[0])
    defer for &index_data in res do delete(index_data)

    testing.expect(t, ok, "ok check")
    log.infof("indices size: %d, num indices: %d", len(res), len(res[0]))
}
*/