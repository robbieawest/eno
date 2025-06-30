package resource

import "vendor:cgltf"

import utils "../utils"
import dbg "../debug"

import "core:testing"
import "core:strings"

DEFAULT_OPTIONS: cgltf.options
load_gltf_mesh_primitives :: proc(path: string) -> (data: ^cgltf.data, result: cgltf.result){
    result = .io_error

    dbg.debug_point(dbg.LogLevel.INFO, "Reading gltf mesh. Path: \"%s\"", path)

    cpath := strings.clone_to_cstring(path)

    data, result = cgltf.parse_file(DEFAULT_OPTIONS, cpath)

    if result != .success {
        dbg.debug_point(dbg.LogLevel.ERROR, "Unable to load gltf mesh. Path: \"%s\"", path)
        return
    }
    if result = cgltf.load_buffers(DEFAULT_OPTIONS, data, cpath); result != .success {
        dbg.debug_point(dbg.LogLevel.ERROR, "Unable to load default buffers for gltf mesh. Path: \"%s\"", path)
        return
    }
    if result = cgltf.validate(data); result != .success {
        dbg.debug_point(dbg.LogLevel.ERROR, "Unable to validate imported data for gltf mesh. Path: \"%s\"", path)
        return
    }
    
    return data, .success
}


@(test)
load_model_test :: proc(t: ^testing.T) {
    data, result := load_gltf_mesh_primitives("SciFiHelmet")
    defer cgltf.free(data)

    testing.expect_value(t, result, cgltf.result.success)
    testing.expect(t, data != nil, "nil check")
    
    //log.infof("data: \n%#v", data)
}


extract_model :: proc(manager: ^ResourceManager, path: string, model_name: string) -> (model: Model, ok: bool) {
    data, res := load_gltf_mesh_primitives(path)
    if res != .success do return

    for mesh in data.meshes {
        if strings.compare(string(mesh.name), model_name) == 0 do return extract_cgltf_mesh(manager, mesh)
    }

    ok = false
    return
}

/*
    Gives an eno mesh for each primitive in the cgltf "mesh"
*/
extract_cgltf_mesh :: proc(manager: ^ResourceManager, mesh: cgltf.mesh) -> (model: Model, ok: bool) {
    //This is assuming all mesh attributes (aside from indices) have the same count (for each primitive/mesh output)

    meshes := make([dynamic]Mesh, len(mesh.primitives))

    for primitive, i in mesh.primitives {
        mesh_ret := &meshes[i]

        // Set material properties
        mesh_ret.material = add_material_to_manager(manager, eno_material_from_cgltf_material(manager, primitive.material^) or_return)

        // Construct layout
        for attribute in primitive.attributes {
            accessor := attribute.data

            attribute_info := MeshAttributeInfo{
                cast(MeshAttributeType)int(attribute.type),
                cast(MeshElementType)int(accessor.type),
                convert_component_type(accessor.component_type),
                u32(accessor.stride),
                u32(accessor.stride >> 2),
                string(accessor.name)
            }
            append(&mesh_ret.layout, attribute_info)
        }


        // Get float stride - the number of floats needed for each vertex

        mesh_ret.vertex_data = extract_vertex_data_from_primitive(primitive) or_return
        mesh_ret.index_data = extract_index_data_from_primitive(primitive) or_return
    }

    ok = true
    model = { meshes }
    return
}


extract_vertex_data_from_primitive :: proc(primitive: cgltf.primitive) -> (result: VertexData, ok: bool) {

    if len(primitive.attributes) == 0 {
        dbg.debug_point(dbg.LogLevel.ERROR, "Primitive must have attributes")
        return
    }

    float_stride: uint = 0; for attribute in primitive.attributes do float_stride += uint(attribute.data.stride) >> 2
    count := primitive.attributes[0].data.count
    result = make(VertexData, float_stride * count)

    element_offset: uint = 0
    for attribute, j in primitive.attributes {
        accessor := attribute.data

        element_size := (accessor.stride) >> 2  // Number of floats in current element

        next_offset := element_offset + element_size
        vertex_offset: uint = 0
        for k in 0..<count {
            raw_vertex_data : [^]f32 = raw_data(result[vertex_offset + element_offset:vertex_offset + next_offset])

            read_res: b32 = cgltf.accessor_read_float(accessor, k, raw_vertex_data, element_size)
            if read_res == false {
                dbg.debug_point(dbg.LogLevel.ERROR, "Error while reading float from accessor, received boolean false")
                return
            }

            vertex_offset += float_stride
        }
        element_offset = next_offset
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
            dbg.debug_point(dbg.LogLevel.ERROR, "Error while reading uint(index) from accessor, received boolean false")
            return
        }

    }

    ok = true
    return
}


@(private)
cgltf_component_type_to_typeid :: proc(type: cgltf.component_type) -> (ret: typeid, ok: bool) {
    switch type {
    case .invalid:
        dbg.debug_point(dbg.LogLevel.ERROR, "Component type is invalid")
        return
    case .r_8: ret = i8
    case .r_8u: ret = u8
    case .r_16: ret = i16
    case .r_16u: ret = u16
    case .r_32u: ret = u32
    case .r_32f: ret = f32
    }

    ok = true
    return
}

@(private)
convert_component_type :: proc(type: cgltf.component_type) -> (ret: MeshComponentType) {
    return cast(MeshComponentType)int(type)
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