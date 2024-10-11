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

GPUComponent :: union {
    gl_GPUComponent,
    vl_GPUComponent
}

gl_GPUComponent :: struct {
    vao, vbo, ebo: u32
}
vl_GPUComponent :: struct {
    vlwhatthefuckwouldgohere: u32
}

release_gpu_component :: proc(component: ^GPUComponent) {
    //Needs to be chunked, how to take in a list and combine a pointer to each element? Definitely some SOA AOS shit check it
    //*want less GPU calls when releasing memory
    switch (RENDER_API) {
    case .OPENGL: 
        comps, ok := component.(gl_GPUComponent) //Not sure if comps is copied here to be honest
        if !ok {
            log.errorf("GPUComponent is not gl yet renderapi gl? What are you doing?")
            return
        }
        gl.DeleteVertexArrays(1, &comps.vao)
        gl.DeleteBuffers(1, &comps.vbo)
        gl.DeleteBuffers(1, &comps.ebo)
        free(components)
    case .VULKAN:
        log.infof("%s: Vulkan not yet supported")
    }
}

//

// Procedures to express mesh structures on the GPU, a shader is assumed to already be attached

express_mesh_with_indices :: proc(mesh: ^model.Mesh, index_data: ^model.IndexData) -> (gpu_component: ^GPUComponent ok: bool) {
    gpu_component = new(GPUComponent)

    ok = express_mesh(mesh, gpu_component)
    if !ok do return gpu_component, ok

    ok = express_indices(index_data, gpu_component)
    if !ok do return gpu_component, ok

    return gpu_component, true
}

//*Likely should use express_mesh_with_indices instead
express_mesh :: proc(mesh: ^model.Mesh, gpu_component: ^GPUComponent) -> (ok: bool) {

    if len(mesh.vertices) == 0 {
        log.errorf("%s: No vertices given to express", #procedure)
        return ok
    }

    switch (RENDER_API) {
    case .OPENGL:
        gl_gpu_component, ok := gpu_component.(gl_GPUComponent) //Extrapolate to surrouding method
        if !ok {
            log.errorf("GPUComponent is not gl yet renderapi gl? What are you doing?")
            return ok 
        }
        gl_express_mesh(mesh, &gl_gpu_component)
    case .VULKAN:
        log.errorf("%s: Vulkan not yet supported", #procedure) //Extrapolate to surrounding method as well
        return ok 
    }

    return true
}

@(private)
gl_express_mesh :: proc(mesh: ^model.Mesh, gl_gpu_component: ^gl_GPUComponent) {
    gl.GenVertexArrays(1, &vao)
    gl.GenBuffers(1, &vbo)
    
    gl.BindVertexArray(vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)

    stride: int = len(mesh.vertices[0].raw_data) * size_of(f32)
    gl.BufferData(vbo, len(mesh.vertices) * stride, raw_data(mesh.vertices), gl.STATIC_DRAW)

    offset, current_ind: u32 = 0, 0
    for size in mesh.layout.sizes {
        gl.EnableVertexAttribArray(current_ind)
        gl.VertexAttribPointer(current_ind, size, gl.FLOAT, gl.FALSE, i32(stride), uintptr(offset))

        offset += u32(size)
        current_ind += 1
    }

    gl_gpu_component.vao = vao
    gl_gpu_component.vbo = vbo
}

//*Likely should use express_mesh_with_indices instead
express_indices :: proc(index_data: ^IndexData, gpu_component: ^GPUComponent) -> (ok: bool) {

    switch (RENDER_API) {
    case .OPENGL: 
        gl_gpu_component, ok := gpu_component.(gl_GPUComponent) //Extrapolate to surrouding method
        if !ok {
            log.errorf("GPUComponent is not gl yet renderapi gl? What are you doing?")
            return ok 
        }

        gl_express_indices(express_indices, &gl_gpu_component)
    case .VULKAN:
        log.errorf("%s: Vulkan not yet supported", #procedure)
        return ok
    }
    
    return true
}

@(private)
gl_express_indices :: proc(index_data: ^IndexData, gl_gpu_component: ^gl_GPUComponent) {
    ebo: u32
    gl.GenBuffers(1, &ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
    gl.BufferData(ebo, len(indeoffset_ofx_data.raw_data) * size_of(u32), raw_data(index_data.raw_data), gl.STATIC_DRAW)

    gl_gpu_component.ebo = ebo
}

//
