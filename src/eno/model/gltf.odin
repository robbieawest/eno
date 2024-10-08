package model 

import "vendor:cgltf"
import "core:log"
import "core:testing"
import "core:strings"
import "core:mem"
import "core:slice"
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

ZeroedSize :: union { uint, int }
zeroed_size_to_size :: proc(zs: ZeroedSize) -> uint {
    ui, ok := zs.(uint)
    if !ok {
        log.errorf("%s: Attempted to obtain size from int in zeroed size", #procedure)
        return 0
    }
    return ui
}

extract_mesh_from_cgltf :: proc(mesh: ^cgltf.mesh, vertex_layout: [][]VertexComponent) -> (result: []^Mesh, ok: bool) {

    //This is assuming all mesh attributes (aside from indices) have the same count (for each primitive/mesh output)

    log.infof("mesh: \n%#v", mesh)
    log.infof("vertex layout: \n%#v", vertex_layout)

    mesh_data := make([dynamic]^Mesh, len(mesh.primitives))
    defer delete(mesh_data)
    
    if len(vertex_layout) != len(mesh.primitives) {
        log.errorf("%s: Number of mesh primitives does not match vertex layout", #procedure)
        return mesh_data[:], false
    }

    for _primitive, i in mesh.primitives {
        log.infof("vertex layout i: \n%#v", vertex_layout[i])
        components := slice.clone(vertex_layout[i])
        log.infof("components: \n%#v, vertex_layout[i]: \n%#v", components, vertex_layout[i])
        mesh_ret := new(Mesh)
        mesh_ret.components = components 
        log.infof("mesh comp: \n%#v", mesh_ret.components)

        if len(vertex_layout[i]) != len(_primitive.attributes) {
            log.errorf("%s: Number of primitive attributes does not match vertex layout", #procedure);
            return mesh_data[:], false
        }

        count_throughout: uint = 0
        current_offset: uint = 0
        for _attribute, j in _primitive.attributes {
            _accessor := _attribute.data

            //Todo: Consider other datatypes by matching component type of accessor against odin type 
            stride_as_index := _accessor.stride / size_of(f32)

            element_size := mesh_ret.components[j].element_size
            log.infof("element size: %d", element_size)
        
            //Validating mesh
            count := _accessor.count
            if count_throughout != 0 && count != count_throughout {
                log.errorf("%s: Attributes/accessors of mesh primitive must contain the same count/number of elements", #procedure)
                return mesh_data[:], false
            } else if count_throughout == 0 {
                utils.append_n_defaults(&mesh_ret.vertices, count)
            }
            count_throughout = count
            //

            //Read in data for all the vertices of this attribute
            next_offset := current_offset + element_size
            for k in 0..<count {
                if (len(mesh_ret.vertices[k].raw_data) == 0) do utils.append_n_defaults(&mesh_ret.vertices[k].raw_data, stride_as_index)
               
                raw_vertex_data : [^]f32 = raw_data(mesh_ret.vertices[k].raw_data[current_offset:next_offset])
                log.infof("raw data: %v", raw_vertex_data[0])

                read_res: b32 = cgltf.accessor_read_float(_accessor, k, raw_vertex_data, element_size)
                if read_res == false {
                    log.errorf("%s: Error while reading float from accessor, received boolean false", #procedure)
                    return mesh_data[:], false
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

extract_index_data_from_mesh :: proc(mesh: ^cgltf.mesh) -> []uint {
    //do things in here
    return []uint{}
}

@(test)
extract_vertex_data_test :: proc(t: ^testing.T) {
    data, result := load_model_data("SciFiHelmet")
    defer cgltf.free(data)

    vertex_layout := [][]VertexComponent{
        make_vertex_components([]uint{3, 3, 4, 2}, []cgltf.attribute_type{
            cgltf.attribute_type.normal,
            cgltf.attribute_type.position,
            cgltf.attribute_type.tangent,
            cgltf.attribute_type.texcoord
        })
    }
    res, ok := extract_mesh_from_cgltf(&data.meshes[0], vertex_layout)
    defer for mesh in res do destroy_mesh(mesh)

    testing.expect(t, ok, "ok check")
    log.infof("meshes size: %d, mesh components: %v, len mesh vertices: %d", len(res), res[0].components, len(res[0].vertices))
}
