package model 

import "vendor:cgltf"

import utils "../utils"
import dbg "../debug"

import "core:log"
import "core:testing"
import "core:strings"
import "core:mem"
import "core:slice"
import "core:fmt"

DEFAULT_OPTIONS: cgltf.options
load_gltf_mesh :: proc(model_name: string) -> (data: ^cgltf.data, result: cgltf.result){
    model_name := strings.clone_to_cstring(model_name)
    defer delete(model_name)
    
    model_path := fmt.caprintf("resources/models/%s/glTF/%s.gltf", model_name, model_name)
    log.infof("model path: %s", model_path)

    data, result = cgltf.parse_file(DEFAULT_OPTIONS, model_path)

    if result != .success {
        log.errorf("%s: .gltf model unable to load - %s", #procedure, result)
        return nil, result
    }
    if result = cgltf.load_buffers(DEFAULT_OPTIONS, data, model_path); result != .success {
        log.errorf("%s: .gltf unable to load buffers - %s", #procedure, result)
        return nil, result
    }
    if result = cgltf.validate(data); result != .success {
        log.errorf("%s: .gltf unable to validate imported data - %s", #procedure, result)
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
extract_gltf_mesh :: proc(mesh: ^cgltf.mesh, vertex_layouts: []VertexLayout) -> (result: []Mesh, ok: bool) {

    //This is assuming all mesh attributes (aside from indices) have the same count (for each primitive/mesh output)

    log.infof("mesh: \n%#v", mesh)
    log.infof("vertex layouts: \n%#v", vertex_layouts)

    mesh_data := make([dynamic]Mesh, len(mesh.primitives))
    defer delete(mesh_data)
    
    if len(vertex_layouts) != len(mesh.primitives) {
        log.errorf("%s: Number of mesh primitives does not match vertex layout", #procedure)
        return result, false
    }

    for _primitive, i in mesh.primitives {
        mesh_ret: Mesh
        mesh_ret.layout = vertex_layouts[i]

        if len(mesh_ret.layout.sizes) != len(_primitive.attributes) {
            log.errorf("%s: Number of primitive attributes does not match vertex layout", #procedure);
            return result, false
        }

        count_throughout: uint = 0
        current_offset: uint = 0
        for _attribute, j in _primitive.attributes {
            _accessor := _attribute.data

            //Todo: Consider other datatypes by matching component type of accessor against odin type (maybe just raise error when found)

            element_size := mesh_ret.layout.sizes[j]
        
            //Validating mesh
            count := _accessor.count
            if count_throughout != 0 && count != count_throughout {
                log.errorf("%s: Attributes/accessors of mesh primitive must contain the same count/number of elements", #procedure)
                return result, false
            } else if count_throughout == 0 {
                utils.append_n_defaults(&mesh_ret.vertices, count)
            }
            count_throughout = count
            //

            //Read in data for all the vertices of this attribute
            next_offset := current_offset + element_size
            for k in 0..<count {
                if (len(mesh_ret.vertices[k].raw_data) == 0) do utils.append_n_defaults(&mesh_ret.vertices[k].raw_data, _accessor.stride)
               
                raw_vertex_data : [^]f32 = raw_data(mesh_ret.vertices[k].raw_data[current_offset:next_offset])

                read_res: b32 = cgltf.accessor_read_float(_accessor, k, raw_vertex_data, element_size)
                if read_res == false {
                    log.errorf("%s: Error while reading float from accessor, received boolean false", #procedure)
                    return result, false
                }
            }
            //

            current_offset = next_offset
        }

        //Slice components and vertices to add to mesh (Consider just storing dynamic arrays in mesh struct)
        mesh_data[i] = mesh_ret
    }

    return mesh_data[:], true
}
*/

/*
    Gives an eno mesh for each primitive in the cgltf "mesh"
*/
extract_cgltf_mesh :: proc(mesh: ^cgltf.mesh) -> (result: []Mesh, ok: bool) {

    //This is assuming all mesh attributes (aside from indices) have the same count (for each primitive/mesh output)

    log.infof("mesh: \n%#v", mesh)

    mesh_data := make([dynamic]Mesh, len(mesh.primitives))
    defer delete(mesh_data)


    // todo maybe remove _ prefix from var names
    for _primitive, i in mesh.primitives {
        mesh_ret: Mesh

        // Construct layout
        for _attribute in _primitive.attributes {
            _accessor := _attribute.data

            attribute_info := MeshAttributeInfo{
                cast(MeshAttributeType)int(_attribute.type),
                cast(MeshElementType)int(_accessor.type),
                u32(_accessor.stride),
                u32(_accessor.stride >> 3)
            }
            append(&mesh_ret.layout, attribute_info)
        }

        // Get float stride - the number of floats needed for each vertex
        float_stride: u32 = 0; for mesh_attribute_info in mesh_ret.layout do float_stride += mesh_attribute_info.float_stride

        element_count_throughout: uint = 0
        element_offset: u32 = 0
        for _attribute, j in _primitive.attributes {
            _accessor := _attribute.data

            //Todo: Consider other datatypes by matching component type of accessor against odin type (maybe just raise error when found)

            element_size := mesh_ret.layout[j].float_stride  // Number of floats in current element
            log.infof("accessor: %#v", _accessor)

            //Validating mesh
            count := _accessor.count
            if element_count_throughout != 0 && count != element_count_throughout {
                log.errorf("%s: Attributes/accessors of mesh primitive must contain the same count/number of elements", #procedure)
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

                read_res: b32 = cgltf.accessor_read_float(_accessor, k, raw_vertex_data, uint(element_size))
                if read_res == false {
                    dbg.debug_point(dbg.LogInfo{ msg = "Error while reading float from accessor", level = .ERROR})
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

extract_index_data_from_mesh :: proc(mesh: ^cgltf.mesh) -> (result: []IndexData, ok: bool) {
    index_data := make([dynamic]IndexData, len(mesh.primitives))
    defer delete(index_data)

    for _primitive, i in mesh.primitives {
        _accessor := _primitive.indices
        indices: IndexData

        utils.append_n_defaults(&indices.raw_data, u32(_accessor.count))
        for k in 0..<_accessor.count {
            raw_index_data: [^]u32 = raw_data(indices.raw_data[k:k+1])
            read_res: b32 = cgltf.accessor_read_uint(_accessor, k, raw_index_data, 1)
            if read_res == false {
                log.errorf("%s: Error while reading uint(index) from accessor, received boolean false", #procedure)
                return result, false
            }

        }

        index_data[i] = indices
    }

    return index_data[:], true
}


@(test)
extract_vertex_data_test :: proc(t: ^testing.T) {
    data, result := load_gltf_mesh("SciFiHelmet")
    defer cgltf.free(data)

    //Expected usage is defined here.
    //destroy_mesh does not clean up the vertex_layout, so you must do it yourself if you allocate a VertexLayout


    res, ok := extract_cgltf_mesh(&data.meshes[0])
    defer for &mesh in res do destroy_mesh(&mesh)

    testing.expect(t, ok, "ok check")
    log.infof("meshes size: %d, mesh components: %v, len mesh vertices: %d", len(res), res[0].layout, len(res[0].vertex_data))
}


@(test)
extract_index_data_test :: proc(t: ^testing.T) {
    data, result := load_gltf_mesh("SciFiHelmet")

    res, ok := extract_index_data_from_mesh(&data.meshes[0])
    defer for &index_data in res do destroy_index_data(&index_data)

    testing.expect(t, ok, "ok check")
    log.infof("indices size: %d, num indices: %d", len(res), len(res[0].raw_data))
}
