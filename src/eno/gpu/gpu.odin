package gpu

import gl "vendor:OpenGL"

import "core:testing"
import "core:log"
import "../model"

GraphicsAPI :: enum { OPENGL, VULKAN } //Making it easy for the future
RENDER_API: GraphicsAPI = GraphicsAPI.OPENGL


// Defined way to store VAO, VBO, EBO in the entity component system
// A link to release_gpu_components should be stored as a component when creating an entity with GPUComponents as another component
// ToDo: Maybe combine these into a single struct?

GPUComponent :: union #no_nil {
    gl_GPUComponent,
    vl_GPUComponent
}


gl_GPUComponent :: struct {
    vao, vbo, ebo: u32
}

vl_GPUComponent :: struct {
    vlwhatthefuckwouldgohere: u32
}


release_gpu_component :: proc(component: GPUComponent) {
    switch RENDER_API {
    case .OPENGL: 
        gl_component := component.(gl_GPUComponent)

        gl.DeleteVertexArrays(1, &gl_component.vao)
        gl.DeleteBuffers(1, &gl_component.vbo)
        gl.DeleteBuffers(1, &gl_component.ebo)
        free(&gl_component)
    case .VULKAN: vulkan_not_supported();
    }
}

//


// Procedures to express mesh structures on the GPU, a shader is assumed to already be attached

express_mesh_with_indices :: proc(mesh: ^model.Mesh, index_data: ^model.IndexData) -> (gpu_component: GPUComponent ok: bool) {

    switch RENDER_API {
    case .OPENGL:
        gl_def_comp: gl_GPUComponent
        gpu_component = gl_def_comp
    case .VULKAN: vulkan_not_supported(); return gpu_component, ok
    } 

    ok = express_mesh_vertices(mesh, gpu_component)
    if !ok do return gpu_component, ok

    ok = express_indices(index_data, gpu_component)
    if !ok do return gpu_component, ok 

    return gpu_component, true
}


//*Likely should use express_mesh_with_indices instead
express_mesh_vertices_ :: proc(mesh: ^model.Mesh, component: GPUComponent) -> (ok: bool)
express_mesh_vertices: express_mesh_vertices_ = gl_express_mesh_vertices


@(private)
gl_express_mesh_vertices :: proc(mesh: ^model.Mesh, component: GPUComponent) -> (ok: bool) {
    if len(mesh.vertices) == 0 { log.errorf("%s: No vertices given to express", #procedure); return ok }

    gl_component := component.(gl_GPUComponent)

    gl.GenVertexArrays(1, &gl_component.vao)
    gl.GenBuffers(1, &gl_component.vbo)
    
    gl.BindVertexArray(gl_component.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, gl_component.vbo)

    stride: int = len(mesh.vertices[0].raw_data) * size_of(f32)
    gl.BufferData(gl_component.vbo, len(mesh.vertices) * stride, raw_data(mesh.vertices), gl.STATIC_DRAW)

    offset, current_ind: u32 = 0, 0
    for size in mesh.layout.sizes {
        gl.EnableVertexAttribArray(current_ind)
        gl.VertexAttribPointer(current_ind, i32(size), gl.FLOAT, gl.FALSE, i32(stride), uintptr(offset))

        offset += u32(size)
        current_ind += 1
    }

    return true
}


//*Likely should use express_mesh_with_indices instead
express_indices_ :: proc(index_data: ^model.IndexData, component: GPUComponent) -> (ok: bool)
express_indices: express_indices_ = gl_express_indices

@(private)
gl_express_indices :: proc(index_data: ^model.IndexData, component: GPUComponent) -> (ok: bool){
    gl_component := component.(gl_GPUComponent)
    gl.GenBuffers(1, &gl_component.ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_component.ebo)
    gl.BufferData(gl_component.ebo, len(index_data.raw_data) * size_of(u32), raw_data(index_data.raw_data), gl.STATIC_DRAW)
    
    return true
}

//

vulkan_not_supported :: proc(location := #caller_location) { log.errorf("%v: Vulkan not supported", location) }
