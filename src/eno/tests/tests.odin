package tests

import gl "vendor:OpenGL"
import SDL "vendor:sdl2"

import dbg "../debug"
import "../ecs"
import "../resource"
import "../standards"

import "core:testing"
import "core:log"
import "core:fmt"

// Tests put here to avoid circular imports, specifically needed for expresses tests which require a render context

@(private)
create_test_render_context :: proc() -> (window: ^SDL.Window, gl_context: SDL.GLContext) {

	window = SDL.CreateWindow("eno engine test win", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, 400, 400, {.OPENGL})
	if window == nil {
		fmt.eprintln("Failed to create window")
		return window, gl_context 
	}
	
    dbg.init_debug_stack()
	gl_context = SDL.GL_CreateContext(window)
	SDL.GL_MakeCurrent(window, gl_context)
	gl.load_up_to(4, 3, SDL.gl_set_proc_address)

    _attr_ret: i32
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(SDL.GLprofile.CORE))
    _attr_ret |= SDL.GL_SetAttribute(.CONTEXT_FLAGS, i32(SDL.GLcontextFlag.DEBUG_FLAG))
    if _attr_ret != 0 do log.errorf("Could not set certain SDL parameters for OpenGL")

    gl.Enable(gl.DEBUG_OUTPUT)
    gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
    gl.DebugMessageCallback(dbg.GL_DEBUG_CALLBACK, nil)

    return window, gl_context 
}

@(test)
express_shader_test :: proc(t: ^testing.T) {
/*
 using shader
 window, gl_context := create_test_render_context()
 defer dbg.destroy_debug_stack()

 vertex_shader: ^ShaderInfo = init_shader(
             []ShaderBinding {
                 { 0, .vec3, "a_position"},
                 { 1, .vec4, "a_colour"}
             }
     )
 add_output(vertex_shader, []ShaderInput {
     { .vec4, "v_colour"}
 })
 add_uniforms(vertex_shader, []ShaderUniform {
     { .mat4, "u_transform"}
 })
 add_functions(vertex_shader, []ShaderFunction {
     {
         .void,
         []ShaderFunctionArgument {},
         "main",
         `    gl_Position = u_transform * vec4(a_position, 1.0);
 v_colour = a_colour;`,
         false
     }
 })

 vertex_source, vertex_ok := build_shader_source(vertex_shader, .VERTEX)
 testing.expect(t, vertex_ok, "vert check")

 fragment_shader: ^ShaderInfo = init_shader()
 add_input(fragment_shader, []ShaderInput {
     { .vec4, "v_colour" }
 })
 add_output(fragment_shader, []ShaderInput {
     { .vec4, "o_colour" }
 })
 add_functions(fragment_shader, []ShaderFunction {
     {
         .void,
         []ShaderFunctionArgument {},
         "main",
         `    o_colour = v_colour;`,
         false
     }
 })

 fragment_source, fragment_ok := build_shader_source(fragment_shader, .FRAGMENT)
 testing.expect(t, fragment_ok, "frag ok check")

 program: ^ShaderProgram = init_shader_program([]^Shader {
     vertex_source, fragment_source
 })
 defer destroy_shader_program(program)

 testing.expect(t, !program.expressed, "not expressed check")

 express_ok := gpu.express_shader(program)
 testing.expect(t, express_ok, "express ok check")

 testing.expect(t, program.expressed, "expressed check")
 */
}

@(test)
query_archetype_test :: proc(t: ^testing.T) {
    log.infof("%d", size_of(resource.Model))
    dbg.init_debug_stack()
    scene := new(ecs.Scene)
    arch, _ := ecs.scene_add_default_archetype(scene, "demo_entities")
    manager := resource.init_resource_manager()

    scene_res, _ := resource.extract_gltf_scene(&manager, standards.MODEL_RESOURCE_PATH + "SciFiHelmet/glTF/SciFiHelmet.gltf")
    helmet_model := scene_res.models[0].model
    world_properties := scene_res.models[0].world_comp

    _ = ecs.archetype_add_entity(scene, arch, "helmet_entity",
        ecs.make_ecs_component_data(resource.MODEL_COMPONENT.label, resource.MODEL_COMPONENT.type, ecs.serialize_data(&helmet_model, size_of(resource.Model))),
        ecs.make_ecs_component_data(standards.WORLD_COMPONENT.label, standards.WORLD_COMPONENT.type, ecs.serialize_data(&world_properties, size_of(standards.WorldComponent))),
        ecs.make_ecs_component_data(standards.VISIBLE_COMPONENT.label, standards.VISIBLE_COMPONENT.type, ecs.serialize_data(true, size_of(bool)))
    )

    _ = ecs.archetype_add_entity(scene, arch, "helmet_entity 2",
        ecs.make_ecs_component_data(resource.MODEL_COMPONENT.label, resource.MODEL_COMPONENT.type, ecs.serialize_data(&helmet_model, size_of(resource.Model))),
        ecs.make_ecs_component_data(standards.WORLD_COMPONENT.label, standards.WORLD_COMPONENT.type, ecs.serialize_data(&world_properties, size_of(standards.WorldComponent))),
        ecs.make_ecs_component_data(standards.VISIBLE_COMPONENT.label, standards.VISIBLE_COMPONENT.type, ecs.serialize_data(false, size_of(bool)))
    )

    isVisibleQueryData := true
    query := ecs.ArchetypeQuery{ components = []ecs.ComponentQuery{
        { label = resource.MODEL_COMPONENT.label, include = true },
        { label = standards.WORLD_COMPONENT.label, include = true },
        { label = standards.VISIBLE_COMPONENT.label, data = &isVisibleQueryData }
    }}
    query_result := ecs.query_archetype(arch, query)

    log.infof("query result: %#v", query_result)
}
