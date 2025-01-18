package demo

import SDL "vendor:sdl2"
import gl "vendor:OpenGL"
import "vendor:cgltf"

import win "../window"
import game "../game"
import "../ecs"
import "../model"
import "../gpu"
import "../render"
import cutils "../camera_utils"
import cam "../camera"

import "core:log"
import "core:math/linalg"
import glm "core:math/linalg/glsl"

// Implement your before_frame and every_frame procedures in a file like this
// APIs for ecs are dogwater right now

// Certain operations are done around this every frame, look inside game pacakge
every_frame :: proc() {
    render.draw_indexed_entities(game.Game.scene, "helmet_arch", "helmet_entity")
    ok := win.swap_window_bufs(game.Game.window); if !ok do log.errorf("could not swap bufs")
}


before_frame :: proc() {

    ok := game.map_sdl_events(
        { SDL.EventType.QUIT, proc() { game.quit_game() }}
    ); if !ok do log.errorf("Could not map SDL event")

    ok = game.map_sdl_key_events(
        { SDL.Keycode.ESCAPE, proc() { game.quit_game() }}
    ); if !ok do log.errorf("Could not map SDL key event")


    helmet_arch, _ := ecs.scene_add_archetype(game.Game.scene, "helmet_arch", context.allocator,
        ecs.make_component_info(gpu.DrawProperties, "draw_properties"),
        ecs.make_component_info(linalg.Vector3f32, "position"),
        ecs.make_component_info(linalg.Vector3f32, "scale")
    )

    position: linalg.Vector3f32 = { 0.0, 0.0, 0.0 }
    scale: linalg.Vector3f32 = { 0.5, 0.5, 0.5 }


    helmet_draw_properties: gpu.DrawProperties
    helmet_draw_properties.mesh, helmet_draw_properties.indices = helmet_mesh_and_indices()
    ok = create_shader_program(&helmet_draw_properties); if !ok do return

    /*
    helmet_gl_comp.program, ok = gpu.read_shader_source({ Express = true }, "./resources/shaders/demo_shader")
    if !ok {
        log.errorf("Error while reading shader source, returning.")
        return
    }
    helmet_draw_properties.gpu_component = helmet_gl_comp
    */

    gpu.express_draw_properties(&helmet_draw_properties)

    ecs.archetype_add_entity(game.Game.scene, helmet_arch, "helmet_entity",
        ecs.make_component_data_untyped_s(&helmet_draw_properties, "draw_properties"),
        ecs.make_component_data_untyped_s(&position, "position"),
        ecs.make_component_data_untyped_s(&scale, "scale")
    )


    // Camera
    ecs.scene_add_camera(game.Game.scene, cutils.init_camera("helmet_cam", glm.vec3{ 0.0, 0.5, -0.2 }))  // Will set the scene viewpoint
    ok = set_uniforms(&helmet_draw_properties); if !ok do return
}


set_uniforms :: proc(draw_properties: ^gpu.DrawProperties) -> (ok: bool) {  // Todo update setting uniforms
    gl_comp := draw_properties.gpu_component.(gpu.gl_GPUComponent)
    program := &gl_comp.program

    // Get scale and position
    archetype := ecs.scene_get_archetype(game.Game.scene, "helmet_arch") or_return
    position_res: []ecs.ComponentData(glm.vec3) = ecs.query_component_from_archetype(archetype, "position", glm.vec3, "helmet_entity") or_return
    assert(len(position_res) == 1)

    scale_res: []ecs.ComponentData(glm.vec3) = ecs.query_component_from_archetype(archetype, "scale", glm.vec3, "helmet_entity") or_return
    assert(len(scale_res) == 1)

    position: ^glm.vec3 = position_res[0].data
    scale: ^glm.vec3 = scale_res[0].data

    // proce: gpu.UniformMatrixProc(f32) = gl.UniformMatrix4fv  check
    // gpu.set_matrix_uniform(program, "m_Model", false, model, proce)
    // matrix indexing and array short with `.x`


    // native swizzling support for arrays



    log.infof("scale: %v", scale_res)
    model := glm.mat4Scale(scale^)
   // model *= glm.mat4Rotate({ 1, 1, 1}, 1.0)
    model *= glm.mat4Translate(position^)
    log.infof("model: %#v", model)

    model_loc := gpu.get_uniform_location(program, "m_Model") or_return
    gl.UniformMatrix4fv(model_loc, 1, false, &model[0, 0])

    view := cam.camera_look_at(game.Game.scene.viewpoint)
    //                         dir       campos      world up
    //view := glm.mat4LookAt({0, 0, -1}, {0, 0, 0}, {0, 1, 0})
    view_loc := gpu.get_uniform_location(program, "m_View") or_return
    gl.UniformMatrix4fv(view_loc, 1, false, &view[0, 0])

    perspective := cam.get_perspective(game.Game.scene.viewpoint)
    log.infof("perspective: %#v", perspective)
    proj_loc := gpu.get_uniform_location(program, "m_Projection") or_return
    gl.UniformMatrix4fv(proj_loc, 1, false, &perspective[0, 0])

    draw_properties.gpu_component = gl_comp
    ok = true
    return
}


@(private)
helmet_mesh_and_indices_direct :: proc() -> (mesh: model.Mesh, indices: model.IndexData) {
    vertex_data: [dynamic]f32 = {
        0.5, 0.5, 0.0,   1.0, 0.0, 0.0,  //tr
        0.5, -0.5, 0.0,  0.0, 1.0, 0.0,  //br
        -0.5, -0.5, 0.0, 0.0, 0.0, 1.0,  //bl
        -0.5, 0.5, 0.0,  1.0, 1.0, 0.0  //tl
    }

    layout: model.VertexLayout
    append_soa(&layout,
        model.MeshAttributeInfo{ .position, .vec3, .f32, 12, 3, "position" },
        model.MeshAttributeInfo{ .color, .vec3, .f32, 12, 3, "colour" }
    )

    mesh = model.Mesh{ vertex_data, layout }

    index_data: [dynamic]u32 = {
        1, 2, 3,
        0, 1, 3
    }

    indices = { index_data }
    return
}

@(private)
helmet_mesh_and_indices :: proc() -> (mesh: model.Mesh, indices: model.IndexData) {
    meshes, index_datas := read_meshes_and_indices_from_gltf("SciFiHelmet")
    return meshes[0], index_datas[0]
}


// Move this into gltf.odin
@(private)
read_meshes_and_indices_from_gltf :: proc(model_name: string) -> (meshes: []model.Mesh, indices: []model.IndexData) {
    data, result := model.load_gltf_mesh(model_name)
    assert(result == .success, "gltf read success assertion") // todo switch to log
    assert(len(data.meshes) > 0, "gltf data meshes available assertion")

    ok := false
    meshes, ok = model.extract_cgltf_mesh(&data.meshes[0])
    if !ok {
        log.error("Failed to read mesh")
        return meshes, indices
    }
    indices, ok = model.extract_index_data_from_mesh(&data.meshes[0])
    if !ok {
        log.error("Failed to read indices")
        return meshes, indices
    }

    return meshes, indices
}


@(private)
create_shader_program :: proc(properties: ^gpu.DrawProperties) -> (ok: bool) {
    sources := make([dynamic]gpu.ShaderSource, 0)
    gl_comp := properties.gpu_component.(gpu.gl_GPUComponent)
    gl_comp.program = gpu.init_shader_program()

    vertex_shader: gpu.Shader
    gpu.shader_layout_from_mesh(&vertex_shader, properties.mesh) or_return

    gpu.add_uniforms(&vertex_shader, { .mat4, "m_Model" })
    gpu.add_uniforms(&vertex_shader, { .mat4, "m_View" })
    gpu.add_uniforms(&vertex_shader, { .mat4, "m_Projection" })

    gpu.add_output(&vertex_shader, { .vec3, "fragColour" })

    gpu.add_functions(&vertex_shader, gpu.init_shader_function(
        .void,
        "main",
        `
            mat4 mvp = m_Projection * m_View * m_Model;
            gl_Position = mvp * vec4(position, 1.0);
            fragColour = position;
        `,
        false
    ))

    append(&sources, gpu.build_shader_source(vertex_shader, .VERTEX) or_return)
    log.infof("Built source: %#v", sources[0].source)


    fragment_shader: gpu.Shader
    gpu.add_output(&fragment_shader, { .vec4, "Colour" })
    gpu.add_input(&fragment_shader, { .vec3, "fragColour" })
    gpu.add_functions(&fragment_shader, gpu.init_shader_function(
        .void,
        "main",
        "   Colour = vec4(fragColour, 1.0);",
        false
    ))

    append(&sources, gpu.build_shader_source(fragment_shader, .FRAGMENT) or_return)
    log.infof("Built source: %#v", sources[1].source)

    gl_comp.program.sources = sources
    gpu.express_shader(&gl_comp.program)

    gpu.attach_program(gl_comp.program)
    gpu.register_uniform(&gl_comp.program, "m_Model")
    gpu.register_uniform(&gl_comp.program, "m_View")
    gpu.register_uniform(&gl_comp.program, "m_Projection")

    properties.gpu_component = gl_comp
    ok = true
    return
}