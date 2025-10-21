package game

import im "../../../libs/dear-imgui/"

import "../ui"
import dbg "../debug"

scene_ui_element : ui.UIElement : proc() -> (ok: bool) {
    im.Begin("Scene")
    defer im.End()

    if Game.scene == nil {
        dbg.log(.ERROR, "Scene is nil")
        return
    }
    scene := Game.scene

    im.Text("N entities: %d", scene.n_Entities)
    im.Text("N archetype: %d", scene.n_Archetypes)
    im.SeparatorText("Archetypes")

    // Uses reflection
    /*
    for archetype in scene.archetypes {
        archetype.
    }
    */


    return true
}