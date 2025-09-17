package render

import im "../../../libs/dear-imgui/"

import "../ui"
import utils "../utils"
import dbg "../debug"
import "../resource"

import "core:strings"
import slice "core:slice"
import "core:strconv"
import "base:intrinsics"
import "core:fmt"

UIRenderBuffer :: enum {
    ENV_FACE_SIZE,
    ENV_TEX_URI,
    IRR_FACE_SIZE,
    PREFILTER_FACE_SIZE,
    BRDF_LUT_SIZE
}

// Not declaring as constant because taking pointer of Buffers is needed for slice.enumerated_array
Buffers := [UIRenderBuffer]cstring {
    .ENV_FACE_SIZE = "##env_face_size",
    .ENV_TEX_URI = "##env_tex_uri",
    .IRR_FACE_SIZE = "##irr_face_size",
    .PREFILTER_FACE_SIZE = "##pref_face_size",
    .BRDF_LUT_SIZE = "##brdf_lut_size"
}

delete_bufs :: proc() -> (ok: bool) {
    return ui.delete_buffers(..slice.enumerated_array(&Buffers))
}

BUF_TEXT_CHAR_LIM :: ui.DEFAULT_TEXT_CHAR_LIMIT
BUF_NUMERIC_CHAR_LIM :: ui.DEFAULT_NUMERIC_CHAR_LIMIT
load_bufs :: proc() -> (ok: bool) {
    settings, settings_ok := GlobalRenderSettings.unapplied_environment_settings.?
    if !settings_ok {
        dbg.log(.ERROR, "Settings must be available to load bufs")
        return
    }

    ibl_settings, ibl_enabled := settings.ibl_settings.?

    buf_infos: [len(UIRenderBuffer)]ui.BufferInit
    buffers := slice.enumerated_array(&Buffers)

    i := 0
    for buf, buf_type in Buffers {
        byte_buf: Maybe([]byte)
        buf_type: UIRenderBuffer = buf_type  // Intellij doesn't know the type

        switch buf_type {
            case .ENV_FACE_SIZE: byte_buf = ui.int_to_buf(settings.environment_face_size, BUF_NUMERIC_CHAR_LIM, Context.allocator) or_return
            case .ENV_TEX_URI: byte_buf = ui.str_to_buf(settings.environment_texture_uri, BUF_TEXT_CHAR_LIM, Context.allocator) or_return
            case .IRR_FACE_SIZE: if ibl_enabled do byte_buf = ui.int_to_buf(ibl_settings.irradiance_map_face_size, BUF_NUMERIC_CHAR_LIM, Context.allocator) or_return
            case .PREFILTER_FACE_SIZE: if ibl_enabled do byte_buf = ui.int_to_buf(ibl_settings.prefilter_map_face_size, BUF_NUMERIC_CHAR_LIM, Context.allocator) or_return
            case .BRDF_LUT_SIZE: if ibl_enabled do byte_buf = ui.int_to_buf(ibl_settings.brdf_lut_size, BUF_NUMERIC_CHAR_LIM, Context.allocator) or_return
        }

        if byte_buf != nil do buf_infos[i] = { buf, byte_buf.? }
        i += 1
    }

    ui.load_buffers(..buf_infos[:])

    for info in buf_infos do delete(info.buf, Context.allocator)

    return true
}

render_settings_ui_element : ui.UIElement : proc() -> (ok: bool) {
    if Context.manager == nil {
        dbg.log(.ERROR, "Render context manager is not yet set")
        return
    }

    im.Begin("Render settings")
    defer im.End()

    if im.TreeNode("Image environment settings") {
        defer im.TreePop()

        if GlobalRenderSettings.environment_settings != nil {
            if im.Button("Disable Image Environment") {
                disable_environment_settings()
                delete_bufs()
                return true
            }
            // Show environment settings
            env_settings: ^EnvironmentSettings = &GlobalRenderSettings.unapplied_environment_settings.?

            im.Text("Environment face size:")
            env_settings.environment_face_size = i32(ui.int_text_input(Buffers[.ENV_FACE_SIZE]) or_return)

            im.Text("Environment texture uri")
            env_settings.environment_texture_uri = ui.text_input(Buffers[.ENV_TEX_URI]) or_return

            if im.TreeNode("IBL Settings") {
                defer im.TreePop()
                if env_settings.ibl_settings == nil {
                    if im.Button("Enable IBL") {
                        env_settings.ibl_settings = make_ibl_settings()
                        // set_environment_settings(env_settings^)
                        apply_environment_settings(Context.manager, Context.allocator) or_return
                        load_bufs() or_return
                        return true
                    }
                }
                else {
                    ibl_settings: ^IBLSettings = &env_settings.ibl_settings.?
                    im.Text("Irradiance map face size:")
                    ibl_settings.irradiance_map_face_size = i32(ui.int_text_input(Buffers[.IRR_FACE_SIZE]) or_return)

                    im.Text("Prefilter map face size:")
                    ibl_settings.prefilter_map_face_size = i32(ui.int_text_input(Buffers[.PREFILTER_FACE_SIZE]) or_return)

                    im.Text("BRDF LUT size:")
                    ibl_settings.brdf_lut_size = i32(ui.int_text_input(Buffers[.BRDF_LUT_SIZE]) or_return)

                    if im.Button("Disable IBL") {
                        disable_ibl_settings()
                        ui.delete_buffers(Buffers[.IRR_FACE_SIZE], Buffers[.PREFILTER_FACE_SIZE], Buffers[.BRDF_LUT_SIZE])
                        return true
                    }
                }
            }

            if im.Button("Apply image environment settings") {
                apply_environment_settings(Context.manager, Context.allocator)
            }
        }
        else do if im.Button("Enable Image Environment") {
            set_environment_settings(make_environment_settings())
            apply_environment_settings(Context.manager, Context.allocator) or_return
            load_bufs() or_return
            return true
        }

    }

    if im.TreeNode("Direct lighting settings") {
        defer im.TreePop()
        if GlobalRenderSettings.direct_lighting_settings != nil {
            if im.Button("Disable direct lighting") {
                disable_direct_lighting()
            }
        }
        else {
            if im.Button("Enable direct lighting") {
                enable_direct_lighting()
            }
        }
    }

    return true
}

render_pipeline_ui_element : ui.UIElement : proc() -> (ok: bool) {
    if Context.manager == nil {
        dbg.log(.ERROR, "Render context manager is not yet set")
        return
    }

    im.Begin("Render pipeline")
    defer im.End()

    if im.TreeNode("Framebuffers") {
        defer im.TreePop()

        framebuffers := Context.pipeline.frame_buffers[:]
        for framebuffer in framebuffers {

            // Stupid, use arena for ui allocations
            tree_str := fmt.caprintf("Framebuffer id %d", framebuffer.id, allocator=Context.allocator)
            defer delete(tree_str)
            if im.TreeNode(tree_str) {
                defer im.TreePop()

                im.Text("Width: %d", framebuffer.w)
                im.Text("Height: %d", framebuffer.h)

                if im.TreeNode("Attachments") {
                    defer im.TreePop()

                    for _, attachment in framebuffer.attachments {
                        attachment_data_type: string
                        is_texture: bool
                        switch _ in attachment.data {
                            case resource.Texture:
                                attachment_data_type = "Texture"
                                is_texture = true

                            case RenderBuffer: attachment_data_type = "Renderbuffer"
                        }
                        attachment_tree_str := fmt.caprintf("%s Attachment of type %v and id '%d'", attachment_data_type, attachment.type, attachment.id, allocator=Context.allocator)
                        defer delete(attachment_tree_str)
                        if im.TreeNode(attachment_tree_str) {
                            defer im.TreePop()

                            if is_texture {
                                tex := attachment.data.(resource.Texture)
                                if tex.gpu_texture != nil {
                                    im.Image(im.TextureID(tex.gpu_texture.(u32)), ui.scale_image_dims(tex.image.w, tex.image.h) or_return )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if im.TreeNode("Render Passes") {
        defer im.TreePop()

    }

    return true
}

shader_store_ui_element : ui.UIElement : proc() -> (ok: bool) {
    im.Begin("Resource Shader Store")
    defer im.End()

    shader_store := Context.pipeline.shader_store
    im.Text("Render Passes:")
    i := 0
    for pass, mapping in shader_store.render_pass_mappings {
        pass_name_cstr := strings.clone_to_cstring(pass.name, Context.allocator)
        defer delete(pass_name_cstr)
        if im.TreeNode(pass_name_cstr) {
            defer im.TreePop()

            if im.TreeNode("Meshes") {
                defer im.TreePop()

                for mesh_id, shader_resource_id in mapping {
                    mesh_tree_name := fmt.caprintf("Mesh id '%d'", mesh_id, allocator=Context.allocator)
                    defer delete(mesh_tree_name)
                    if im.TreeNode(mesh_tree_name) {
                        defer im.TreePop()

                        resource_id_name := fmt.caprintf("Resource ident hash '%d' node '%p'", shader_resource_id.hash, rawptr(shader_resource_id.node), allocator=Context.allocator)
                        defer delete(resource_id_name)
                        if im.TreeNode(resource_id_name) {
                            defer im.TreePop()

                            shader_pass, shader_pass_found := resource.get_shader_pass(Context.manager, shader_resource_id)
                            if shader_pass_found do shader_pass_ui(shader_pass) or_return
                            else do im.Text("Shader pass unavailable")
                        }
                    }
                }
            }
        }
    }

    return true
}


shader_pass_ui :: proc(pass: ^resource.ShaderProgram) -> (ok: bool) {

    for type, shader in pass.shaders {
        shader_tree_name := fmt.caprintf("Shader of type %v", type, allocator=Context.allocator)
        defer delete(shader_tree_name)

        if im.TreeNode(shader_tree_name) {
            defer im.TreePop()
            shader, shader_ok := resource.get_shader(Context.manager, shader)
            if shader_ok do shader_ui(shader)
            else do im.Text("Shader unavailable")
        }
    }

    return true
}

shader_ui :: proc(shader: ^resource.Shader) -> (ok: bool) {

    if im.Button("Open string source popup") {
        im.OpenPopup("#shader_popup")
    }

    if im.BeginPopup("#shader_popup") {
        defer im.EndPopup()
        source_cstr := strings.clone_to_cstring(shader.source.string_source, Context.allocator)
        defer delete(source_cstr)
        im.Text("%s", source_cstr)
    }

    return true
}

resource_manager_ui_element : ui.UIElement : proc() -> (ok: bool) {
    im.Begin("Resource Manager")
    defer im.End()

    return true
}
