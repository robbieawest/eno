package model 

import "vendor:cgltf"
import "core:log"
import "core:testing"
import "core:strings"
import "core:mem"
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

    mesh_data := make([dynamic]^Mesh, len(mesh.primitives))
    defer delete(mesh_data)
    
    if len(vertex_layout) != len(mesh.primitives) {
        log.errorf("%s: Number of mesh primitives does not match vertex layout", #procedure)
        return mesh_data[:], false
    }

    for _primitive, i in mesh.primitives {
        mesh_ret := new(Mesh)
        num_copied := utils.copy_slice_to_dynamic(&mesh_ret.components, &vertex_layout[i])
        if !num_copied {
            log.errorf("%s: Error in slice/dynamic arr data", #procedure)
            return mesh_data[:], false
        }

        if len(vertex_layout) != len(_primitive.attributes) {
            log.errorf("%s: Number of primitive attributes does not match vertex layout", #procedure);
            return mesh_data[:], false
        }

        count_throughout: uint = 0
        last_offset: ZeroedSize = -1
        for _attribute, j in _primitive.attributes {
            _accessor := _attribute.data

            //Grab the element size( aligned with the current datatype, in units of that datatype (only currently considering f32) )
            //Todo: Consider other datatypes by matching component type of accessor against odin type 
            stride_as_index : = _accessor.stride / size_of(f32)
            element_size : ZeroedSize = -1
            if _, ok := last_offset.(int); ok {
                if len(vertex_layout[i]) == 1 do element_size = stride_as_index
                else do element_size = vertex_layout[i][j + 1].offset //Panics if vertex_layout incorrectly formatted
            }
            else do element_size = vertex_layout[i][j].offset - zeroed_size_to_size(last_offset)

            
            count := _accessor.count
            if count_throughout != 0 && count != count_throughout {
                log.errorf("%s: Attributes/accessors of mesh primitive must contain the same count/number of elements", #procedure)
                return mesh_data[:], false
            } else if count_throughout == 0 {
                utils.append_n_defaults(&mesh_ret.vertices, count)
                utils.append_n_defaults(&mesh_ret.components, count)
            }

            //Read in data for all the vertices of this attribute
            log.info("hi ", count, " ", count_throughout)
            for k in 0..<count {
                if (len(mesh_ret.vertices[k].raw_data) == 0) do utils.append_n_defaults(&mesh_ret.vertices[k].raw_data, stride_as_index)
                read_res: b32 = cgltf.accessor_read_float(_accessor, k, &mesh_ret.vertices[k].raw_data[vertex_layout[i][j].offset], zeroed_size_to_size(element_size))
                if read_res == false {
                    log.errorf("%s: Error while reading float from accessor, received boolean false", #procedure)
                    return mesh_data[:], false
                }
            }
            log.info("hey")

            last_offset := vertex_layout[i][j].offset
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
        make_vertex_components([]uint{3, 3, 2, 2}, []cgltf.attribute_type{
            cgltf.attribute_type.normal,
            cgltf.attribute_type.position,
            cgltf.attribute_type.tangent,
            cgltf.attribute_type.texcoord
        })
    }
    res, ok := extract_mesh_from_cgltf(&data.meshes[0], vertex_layout)

    testing.expect(t, ok, "ok check")
    log.infof("meshes size: %d, mesh components: %v, len mesh vertices: %d", len(res), res[0].components, len(res[0].vertices))
}

