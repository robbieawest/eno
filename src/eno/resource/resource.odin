package resource

import "../resource"
import "../shader"

// Package defining the resource manager and relevant systems relating to it

ShaderID :: u32  // Referring to full shader pipelines

ResourceManager :: struct {
    materials: map[MaterialID]Material,
    shaders: map[ShaderID]shader.ShaderProgram,
    textures: map[TextureID]Texture
}

init_resource_manager :: proc() -> ResourceManager {
    return ResourceManager {
        make(map[MaterialID]Material),
        make(map[ShaderID]shader.ShaderProgram),
        make(map[TextureID]Texture)
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