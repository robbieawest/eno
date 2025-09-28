package render

import gl "vendor:OpenGL"

import dbg "../debug"
import "../resource"

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