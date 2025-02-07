package render

import gl "vendor:OpenGL"


Pipeline :: struct {
    passes: ^RenderPass
}

RenderPass :: struct {
    frame_buffer: FrameBuffer
}

FrameBuffer :: struct {
    id: u32,
    //store attachments
}


generate_framebuffer :: proc() -> (frame_buffer: FrameBuffer, ok: bool) {
    gl.GenFramebuffers(1, &frame_buffer.id)
    ok = gl.CheckFramebufferStatus(frame_buffer.id) == gl.FRAMEBUFFER_COMPLETE
}


bind_final_render_buffer :: proc() {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

// !!!
// todo if last render pass has an attached renderbuffer, then blit that renderbuffer to final frame
// if its not a renderbuffer but a texture buffer then just render that texture onto a single quad