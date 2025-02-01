package model 

import "vendor:cgltf"

import utils "../utils"
import dbg "../debug"

import "core:log"
import "core:testing"
import "core:strings"
import "core:fmt"

DEFAULT_OPTIONS: cgltf.options
load_gltf_mesh :: proc(model_name: string) -> (data: ^cgltf.data, result: cgltf.result){
    model_name := strings.clone_to_cstring(model_name)
    defer delete(model_name)
    
    model_path := fmt.caprintf("resources/models/%s/glTF/%s.gltf", model_name, model_name)
    dbg.debug_point(dbg.LogLevel.INFO, "Reading gltf mesh. Path: \"%s\"", model_path)

    data, result = cgltf.parse_file(DEFAULT_OPTIONS, model_path)

    if result != .success {
        dbg.debug_point(dbg.LogLevel.ERROR, "Unable to load gltf mesh. Path: \"%s\"", model_path)
        return nil, result
    }
    if result = cgltf.load_buffers(DEFAULT_OPTIONS, data, model_path); result != .success {
        dbg.debug_point(dbg.LogLevel.ERROR, "Unable to load default buffers for gltf mesh. Path: \"%s\"", model_path)
        return nil, result
    }
    if result = cgltf.validate(data); result != .success {
        dbg.debug_point(dbg.LogLevel.ERROR, "Unable to validate imported data for gltf mesh. Path: \"%s\"", model_path)
        return nil, result
    }
    
    return data, .success
}


@(test)
load_model_test :: proc(t: ^testing.T) {
    data, result := load_gltf_mesh("SciFiHelmet")
    defer cgltf.free(data)

    testing.expect_value(t, result, cgltf.result.success)
    testing.expect(t, data != nil, "nil check")
    
    //log.infof("data: \n%#v", data)
}


/*
    Gives an eno mesh for each primitive in the cgltf "mesh"
*/
extract_cgltf_mesh :: proc(mesh: cgltf.mesh) -> (result: []Mesh, ok: bool) {
    //This is assuming all mesh attributes (aside from indices) have the same count (for each primitive/mesh output)

    mesh_data := make([dynamic]Mesh, len(mesh.primitives))

    for primitive, i in mesh.primitives {
        mesh_ret := &mesh_data[i]

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
        float_stride: u32 = 0; for mesh_attribute_info in mesh_ret.layout do float_stride += mesh_attribute_info.float_stride

        element_count_throughout: uint = 0
        element_offset: u32 = 0
        for attribute, j in primitive.attributes {
            accessor := attribute.data

            element_size := mesh_ret.layout[j].float_stride  // Number of floats in current element

            //Validating mesh
            count := accessor.count
            if element_count_throughout != 0 && count != element_count_throughout {
                dbg.debug_point(dbg.LogLevel.ERROR, "Attributes/accessors of mesh primitive must contain the same count/number of elements")
                return result, false
            } else if element_count_throughout == 0 {
                // Initializes vertex data for entire mesh
                utils.append_n_defaults(&mesh_ret.vertex_data, float_stride * u32(count))
            }
            element_count_throughout = count


            next_offset := element_offset + element_size
            vertex_offset: u32 = 0
            for k in 0..<count {
                raw_vertex_data : [^]f32 = raw_data(mesh_ret.vertex_data[vertex_offset + element_offset:vertex_offset + next_offset])

                read_res: b32 = cgltf.accessor_read_float(accessor, k, raw_vertex_data, uint(element_size))
                if read_res == false {
                    dbg.debug_point(dbg.LogLevel.ERROR, "Error while reading float from accessor, received boolean false")
                    return
                }

                vertex_offset += float_stride
            }
            element_offset = next_offset
        }

    }

    ok = true
    result = mesh_data[:]
    return
}


extract_index_data_from_mesh :: proc(mesh: cgltf.mesh) -> (result: []IndexData, ok: bool) {
    index_data := make([dynamic]IndexData, len(mesh.primitives))

    for _primitive, i in mesh.primitives {
        _accessor := _primitive.indices
        indices: IndexData

        utils.append_n_defaults(&indices.raw_data, u32(_accessor.count))
        for k in 0..<_accessor.count {
            raw_index_data: [^]u32 = raw_data(indices.raw_data[k:k+1])
            read_res: b32 = cgltf.accessor_read_uint(_accessor, k, raw_index_data, 1)
            if read_res == false {
                dbg.debug_point(dbg.LogLevel.ERROR, "Error while reading uint(index) from accessor, received boolean false")
                return
            }

        }

        index_data[i] = indices
    }

    return index_data[:], true
}


extract_texture_data_from_mesh :: proc(mesh: cgltf.mesh) {
    mesh.primitives[0].material.
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



@(test)
extract_vertex_data_test :: proc(t: ^testing.T) {
    data, result := load_gltf_mesh("SciFiHelmet")
    defer cgltf.free(data)

    //Expected usage is defined here.
    //destroy_mesh does not clean up the vertex_layout, so you must do it yourself if you allocate a VertexLayout


    res, ok := extract_cgltf_mesh(data.meshes[0])
    defer for &mesh in res do destroy_mesh(&mesh)

    testing.expect(t, ok, "ok check")
    testing.expect_value(t, 70074, len(res[0].vertex_data) / 12)
    log.infof("meshes size: %d, mesh components: %#v, len mesh vertices: %d", len(res), res[0].layout, len(res[0].vertex_data) / 12)
}


@(test)
extract_index_data_test :: proc(t: ^testing.T) {
    data, result := load_gltf_mesh("SciFiHelmet")

    res, ok := extract_index_data_from_mesh(data.meshes[0])
    defer for &index_data in res do destroy_index_data(&index_data)

    testing.expect(t, ok, "ok check")
    log.infof("indices size: %d, num indices: %d", len(res), len(res[0].raw_data))
}


load_and_extract_meshes :: proc(model_name: string) -> (meshes: []Mesh, indices: []IndexData, ok: bool) {
    gltf_data, result := load_gltf_mesh(model_name)

    if result != .success {
        dbg.debug_point(dbg.LogLevel.ERROR, "Unsuccessful attempt at loading model")
        return
    }

    if len(gltf_data.meshes) == 0 {
        dbg.debug_point(dbg.LogLevel.ERROR, "GLTF Model contained no meshes")
        return
    }

    meshes_dyna := make([dynamic]Mesh)
    indices_dyna := make([dynamic]IndexData)
    for mesh in gltf_data.meshes {
        meshes_got, meshes_ok := extract_cgltf_mesh(mesh); if !meshes_ok do return
        append_elems(&meshes_dyna, ..meshes_got)

        indices_got, indices_ok := extract_index_data_from_mesh(mesh); if !indices_ok do return
        append_elems(&indices_dyna, ..indices_got)
    }

    return meshes_dyna[:], indices_dyna[:], true
}