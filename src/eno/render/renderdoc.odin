package render

import rdoc "../../../libs/odin-renderdoc"

import dbg "../debug"
import "core:dynlib"

RENDERDOC_API_LOC : string : #config(RENDERDOC_API_LOC, "unavailable")

RenderDoc :: struct {
    lib: dynlib.Library,
    api: rawptr
}

load_renderdoc :: proc() -> (renderdoc: RenderDoc, ok: bool) {
    if RENDERDOC_API_LOC == "unavailable" {
        dbg.log(.INFO, "Renderdoc will not initialize, api loc env not given")
        return
    }

    renderdoc.lib, renderdoc.api, ok = rdoc.load_api(RENDERDOC_API_LOC)

    if !ok {
        dbg.log(.WARN, "Attempted to load rdoc api, failed")
        return
    }

    Context.renderdoc = renderdoc

    ok = true
    return
}

unload_renderdoc :: proc(rdoc_lib: dynlib.Library) {
    rdoc.unload_api(rdoc_lib)
}