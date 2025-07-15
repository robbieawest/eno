package resource

import "../shader"

import "core:log"
import standards "../standards"

// Package defining the resource manager and relevant systems relating to it

ShaderID :: u32  // Referring to full shader pipelines

ResourceManager :: struct {
    materials: map[MaterialID]Material,
    shaders: map[ShaderID]shader.ShaderProgram,
    textures: map[TextureID]Texture,
    billboard_shader: Maybe(ShaderID)
}

init_resource_manager :: proc(allocator := context.allocator) -> ResourceManager {
    return ResourceManager {
        make(map[MaterialID]Material, allocator=allocator),
        make(map[ShaderID]shader.ShaderProgram, allocator=allocator),
        make(map[TextureID]Texture, allocator=allocator),
        nil
    }
}

add_texture_to_manager :: proc(manager: ^ResourceManager, texture: Texture) -> TextureID {
    new_id := u32(len(manager.textures))
    manager.textures[new_id] = texture
    return new_id
}

add_shader_to_manager :: proc(manager: ^ResourceManager, program: shader.ShaderProgram) -> ShaderID {
    new_id := u32(len(manager.shaders))
    manager.shaders[new_id] = program
    return new_id
}

add_material_to_manager :: proc(manager: ^ResourceManager, material: Material) -> MaterialID {
    new_id := u32(len(manager.materials))
    manager.materials[new_id] = material
    return new_id
}

get_texture :: proc(manager: ^ResourceManager, id: TextureID) -> ^Texture {
    if id not_in manager.textures do return nil
    return &manager.textures[id]
}

get_material :: proc(manager: ^ResourceManager, id: MaterialID) -> ^Material {
    if id not_in manager.materials do return nil
    return &manager.materials[id]
}

get_shader :: proc(manager: ^ResourceManager, id: ShaderID) -> ^shader.ShaderProgram{
    if id not_in manager.shaders do return nil
    return &manager.shaders[id]
}

get_billboard_lighting_shader :: proc(manager: ^ResourceManager) -> (result: ShaderID, ok: bool) {
    if manager.billboard_shader == nil || manager.billboard_shader.? not_in manager.shaders {
        program := shader.read_shader_source(standards.SHADER_RESOURCE_PATH + "billboard.vert", standards.SHADER_RESOURCE_PATH + "billboard.frag") or_return
        result = add_shader_to_manager(manager, program)
        manager.billboard_shader = result
        return result, true
    }
    return manager.billboard_shader.?, true
}