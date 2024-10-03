package model 

import "vendor:cgltf"
import "core:log"
import "core:testing"
import "core:strings"
import "../utils"

DEFAULT_OPTIONS: cgltf.options
load_model_data :: proc(model_name: string) -> (data: ^cgltf.data, result: cgltf.result){
    model_name := strings.clone_to_cstring(model_name)
    defer delete(model_name)

    model_path := utils.concat_cstr("resources/models/", model_name, "/glTF/", model_name, ".gltf")
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
    data, result := load_model_data("SciFiHelmet")
    defer cgltf.free(data)

    testing.expect_value(t, result, cgltf.result.success)
    testing.expect(t, data != nil, "nil check")
    
    //log.infof("data: \n%#v", data)
}

extract_vertex_data_from_mesh :: proc(mesh: ^cgltf.mesh) -> (result: []^Mesh, ok: bool) {

    //This is assuming all mesh attributes (aside from indices) have the same count (for each primitive/mesh output)

    log.infof("mesh: \n%#v", mesh)

    mesh_data := make([dynamic]^Mesh, len(mesh.primitives))
    defer delete(mesh_data)

    for _primitive, i in mesh.primitives {
        mesh_ret := new(Mesh)

        components := make([dynamic]VertexComponent)
        defer delete(components)
        vertices := make([dynamic]VertexData)
        defer delete(vertices)

        count_throughout: uint = 0
        current_offset: uint = 0
        for _attribute, j in _primitive.attributes {
            _accessor := _attribute.data

            //Grab the element size( aligned with the current datatype, in units of that datatype (only currently considering f32) )
            //Todo: Consider other datatypes by matching component type of accessor against odin type 
            element_size := _accessor.stride / _accessor.count / size_of(f32)
            
            count := _accessor.count
            if count_throughout != 0 && count != count_throughout {
                log.errorf("%s: Attributes/accessors of mesh primitive must contain the same count/number of elements", #procedure)
                return mesh_data[:], false
            } else if count_throughout == 0 {
                utils.append_n_defaults(&vertices, count)
                utils.append_n_defaults(&components, count)
            }

            //Read in data for all the vertices of this attribute
            for k in 0..<count {
                read_res: b32 = cgltf.accessor_read_float(_accessor, k, &mesh_ret.vertices[k].raw_data[current_offset], element_size)
                if read_res == false {
                    log.errorf("%s: Error while reading float from accessor, received boolean false", #procedure)
                    return mesh_data[:], false
                }
            }

            current_offset += element_size
            components[j] = VertexComponent{ current_offset, _attribute.type }
        }

        //Slice components and vertices to add to mesh (Consider just storing dynamic arrays in mesh struct)
        mesh_ret.components = components[:]
        mesh_ret.vertices = vertices[:]
        mesh_data[i] = mesh_ret
    }

    return mesh_data[:], true
}

extract_index_data_from_mesh :: proc(mesh: ^cgltf.mesh) -> []uint {
    //do things in here
    return []uint{}
}

@(test)
extract_vertex_data_test :: proc(t: ^testing.T) {
    data, result := load_model_data("SciFiHelmet")
    defer cgltf.free(data)

    res, ok := extract_vertex_data_from_mesh(&data.meshes[0])
    testing.expect(t, ok, "ok check")
    log.infof("meshes size: %d, mesh components: %v, len mesh vertices: %d", len(res), res[0].components, len(res[0].vertices))
}

