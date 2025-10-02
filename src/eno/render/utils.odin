package render

import gl "vendor:OpenGL"

import "../resource"
import "../utils"
import dbg "../debug"

import "core:fmt"

create_cubemap_from_2d :: proc(tex: resource.Texture, properties: resource.TextureProperties) -> (cubemap: resource.Texture, ok: bool) {
    if tex.type != .TWO_DIM {
        dbg.log(.ERROR, "Input texture must be 2D")
        return
    }
    if tex.gpu_texture == nil {
        dbg.log(.ERROR, "Input texture is not yet transferred")
        return
    }
    inp_tex_gpu := tex.gpu_texture.(u32)

    cubemap = resource.Texture{ image = resource.Image{ w = tex.image.w, h = tex.image.h, channels = tex.image.channels }, type = .CUBEMAP, properties = properties }
    cubemap.gpu_texture = make_texture(cubemap, set_storage=true)
    cube_gpu := cubemap.gpu_texture.(u32)

    for i in 0..<6 {
        gl.CopyImageSubData(inp_tex_gpu, gl.TEXTURE_2D, 0, 0, 0, 0, cube_gpu, gl.TEXTURE_CUBE_MAP, 0, 0, 0, i32(i), tex.image.w, tex.image.h, 1)
    }

    ok = true
    return
}
set_uniform_of_extended_type :: proc(program: ^resource.ShaderProgram, label: string, type: resource.ExtendedGLSLType, data: []u8, cur_tex_unit: ^i32 = nil, temp_allocator := context.temp_allocator) -> (ok: bool) {
    _, uniform_found := resource.get_uniform_location(program, label); if !uniform_found do return true

    switch glsl_type_variant in type {
    case resource.GLSLDataType: set_uniform_of_type(program, label, glsl_type_variant, data, cur_tex_unit) or_return
    case resource.GLSLFixedArray:
        uniform_type := resource.get_uniform_type_from_glsl_type(glsl_type_variant.type)
        uniform_type_size := type_info_of(uniform_type).size

        data_idx := 0
        next_data_idx: int
        for i in 0..<len(data) / uniform_type_size {
            inner_label := fmt.aprintf("%s[%d]", label, i, allocator=temp_allocator)
            next_data_idx = data_idx + uniform_type_size
            set_uniform_of_type(program, inner_label, glsl_type_variant.type, data[data_idx:next_data_idx]) or_return
            data_idx = next_data_idx
        }
    case resource.ShaderStructID, resource.GLSLVariableArray: dbg.log(.WARN, "GLSL type variant not supported")
    }


    return true
}

// Will bind textures to the cur tex unit if needed!
set_uniform_of_type :: proc(shader: ^resource.ShaderProgram, label: string, type: resource.GLSLType, data: []u8, cur_tex_unit : ^i32 = nil) -> (ok: bool) {
    // dbg.log(.INFO, "Setting uniform %s of type: %v", label, type)
    switch type {
    case .uint:
        val: u32 = utils.cast_bytearr_to_type(u32, data) or_return
        resource.Uniform1ui(shader, label, val)
    case .float:
        val: f32 =  utils.cast_bytearr_to_type(f32, data) or_return
        resource.Uniform1f(shader, label, val)
    case .vec2:
        val: [2]f32 = utils.cast_bytearr_to_type([2]f32, data) or_return
        resource.Uniform2f(shader, label, val[0], val[1])
    case .vec3:
        val: [3]f32 = utils.cast_bytearr_to_type([3]f32, data) or_return
        resource.Uniform3f(shader, label, val[0], val[1],val[2])
    case .vec4:
        val: [4]f32 = utils.cast_bytearr_to_type([4]f32, data) or_return
        resource.Uniform4f(shader, label, val[0], val[1], val[2], val[3])
    case .sampler2D:
        if cur_tex_unit == nil {
            dbg.log(.ERROR, "Cur tex unit must be given when the glsl type is sampler2D")
            return
        }

        val: resource.Texture = utils.cast_bytearr_to_type(resource.Texture, data) or_return
        gpu_tex, gpu_tex_available := val.gpu_texture.?
        if !gpu_tex_available {
            dbg.log(.ERROR, "Texture must be transferred to be able to set it as a uniform")
            return
        }

        bind_texture(cur_tex_unit^, gpu_tex, val.type) or_return
        resource.Uniform1i(shader, label, cur_tex_unit^)
        cur_tex_unit^ += 1
    // ..todo
    case: dbg.log(.WARN, "GLSL type %v not yet supported", type)
    }
    return true
}
