package render

import "../ecs"


RenderType :: enum u32 {
    COLOUR = gl.COLOR_BUFFER_BIT,
    DEPTH = gl.DEPTH_BUFFER_BIT,
    STENCIL = gl.STENCIL_BUFFER_BIT
}
RenderMask :: bit_set[RenderType]

ColourMask :: RenderMask{ .COLOUR }
DepthMask :: RenderMask{ .DEPTH }
StencilMask :: RenderMask{ .STENCIL }


render :: proc(pipeline: RenderPipeline, scene: ^ecs.Scene) {
    // search scene for drawable models (cached?)
    // make it non cached for now


}