package ecs

import dbg "../debug"

import "core:mem"
import "core:slice"
import glm "core:math/linalg/glsl"

// Todo: look into component/entity deletion and custom allocators
// Relate it to every type defined in eno

// Todo: Implement
ChunkAllocator :: struct {
    
}


Entity :: struct {
    id: u32,
    archetype_column: u32
}


ComponentInfo :: struct {
    size: u32,  // In bytes
    label: string,
    type: typeid
}

make_component_info :: proc(T: typeid, label: string) -> ComponentInfo {
    return ComponentInfo{ size = size_of(T), label = label, type = T }
}

ArchetypeComponentInfo :: struct {
    total_size_per_entity: u32,
    component_infos: []ComponentInfo
}

ARCHETYPE_MAX_COMPONENTS : u32 : 0x000FFFFF
ARCHETYPE_MAX_ENTITIES : u32 : 0x00FFFFFF 
ARCHETYPE_INITIAL_ENTITIES_CAPACITTY : u32 : 100
Archetype :: struct {
    n_Entities: u32,
    entities: map[string]Entity,  // Allocated using default heap allocator/context allocator
    n_Components: u32,
    components_allocator: mem.Allocator,
    components: [dynamic][dynamic]byte,  // shape: ARCHETYPE_MAX_COMPONENTS * ARCHETYPE_MAX_ENTITIES
    component_info: ArchetypeComponentInfo,
    components_label_match: map[string]u32 // Matches a label to an index from the components array
}

SCENE_MAX_ENTITIES : u32 : 0xFFFFFFFF
Scene :: struct {
    n_Entities: u32,
    n_Archetypes: u32,
    archetypes: [dynamic]Archetype,
    archetype_label_match: map[string]u32,  // Maps string label to index in archetypes
    allocated: bool,
    cameras: [dynamic]Camera,
    viewpoint: ^Camera
}

// Scene should be stack allocated if possible
init_scene :: proc() -> (scene: ^Scene) {
    scene = new(Scene)
    scene.allocated = true
    //scene.archetype_label_match = make(map[string]u32, 0)
    return
}


// Does not free top level archetype
destroy_archetype :: proc(archetype: ^Archetype, allocator := context.allocator, loc := #caller_location) {
    delete(archetype.entities, loc)
    delete(archetype.component_info.component_infos, allocator, loc)
    delete(archetype.components_label_match, loc)
    
    for component_data in archetype.components do delete(component_data, loc)
    delete(archetype.components, loc)
}


// Does not free top level scene
destroy_scene :: proc(scene: ^Scene, allocator := context.allocator, loc := #caller_location) {
    delete(scene.archetype_label_match, loc)
    delete(scene.cameras)

    for &archetype in scene.archetypes do destroy_archetype(&archetype, allocator, loc)
    delete(scene.archetypes, loc)

    if scene.allocated do free(scene, allocator, loc)
}


scene_get_archetype :: proc(scene: ^Scene, archetype_label: string) -> (archetype: ^Archetype, ok: bool) {
    archetype_index, archetype_exists := scene.archetype_label_match[archetype_label]
    if !archetype_exists {
    dbg.debug_point(dbg.LogLevel.ERROR, "Attempted to retreive archetype from label which does not map to any archetype")
        return
    }

    return &scene.archetypes[archetype_index], true
}

// Unchecked component_label, should really not use unless it is already verified
archetype_get_component_data :: proc(archetype: ^Archetype, component_label: string, m: u32, n: u32) -> (component_data: []byte) {
    
    component_index := archetype.components_label_match[component_label]

    comp_data: ^[dynamic]byte = &archetype.components[component_index]
    return comp_data[m:min(n, u32(len(comp_data)))]
}

archetype_get_component_data_from_column :: proc(archetype: ^Archetype, component_label: string, column: int) -> (component: Component) {

    component_index := archetype.components_label_match[component_label]
    component_info := archetype.component_info.component_infos[component_index]
    comp_data: ^[dynamic]byte = &archetype.components[component_index]
    into_data := column * int(component_info.size)

    return Component {label = component_label, data = comp_data[into_data:into_data + int(component_info.size)] , type = component_info.type }
}


scene_add_archetype :: proc(scene: ^Scene, new_label: string, components_allocator: mem.Allocator, component_infos: ..ComponentInfo) -> (ret: ^Archetype, ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "New archetype in scene: %s", new_label)

    duplicate_archetype := new_label in scene.archetype_label_match
    if duplicate_archetype {
        dbg.debug_point(dbg.LogLevel.ERROR, "Attempted to create archetype with a duplicate label")
        return
    }
    

    archetype: Archetype
    for component_info in component_infos {
        archetype.component_info.total_size_per_entity += component_info.size
    }
    archetype.component_info.component_infos = slice.clone(component_infos)

    archetype.components_allocator = components_allocator 
    archetype.n_Components = u32(len(component_infos))
    archetype.components = make([dynamic][dynamic]byte, len(component_infos))

    for component_info, i in component_infos {
        duplicate_component := component_info.label in archetype.components_label_match
        if duplicate_component {
            dbg.debug_point(dbg.LogLevel.ERROR, "Attempted to create component with a duplicate label")
            return
        }

        archetype.components[i] = make([dynamic]byte, 0, ARCHETYPE_INITIAL_ENTITIES_CAPACITTY * component_info.size, components_allocator)

        archetype.components_label_match[component_info.label] = u32(i)
    }

    scene.archetype_label_match[new_label] = scene.n_Archetypes
    append(&scene.archetypes, archetype)
    scene.n_Archetypes += 1
    ok = true
    ret = &scene.archetypes[len(scene.archetypes) - 1]
    return
}

/*
   Adds entities of a single archetype
   Input is serialized component data
*/

scene_add_entities :: proc(scene: ^Scene, archetype_label: string, entity_component_data: map[string][]ComponentDataUntyped) -> (ok: bool) {
    archetype: ^Archetype = scene_get_archetype(scene, archetype_label) or_return
    for entity_label, component_data in entity_component_data {
        archetype_add_entity(scene, archetype, entity_label, ..component_data) or_return
    }

    ok = true
    return
}



@(private)
archetype_add_entity_checks :: proc(scene: ^Scene, archetype: ^Archetype, entity_label: string) -> (ok: bool) {
    duplicate_entity_label := entity_label in archetype.entities
    if duplicate_entity_label {
        dbg.debug_point(dbg.LogLevel.ERROR, "Attempted to create entity with a duplicate label")
        return
    }

    if scene.n_Entities == SCENE_MAX_ENTITIES {
        dbg.debug_point(dbg.LogLevel.ERROR, "Max entities limit for scene reached: %d", SCENE_MAX_ENTITIES)
        return
    }
    
    if archetype.n_Entities == ARCHETYPE_MAX_ENTITIES {
        dbg.debug_point(dbg.LogLevel.ERROR, "Max entities limit for archetype reached: %d", ARCHETYPE_MAX_ENTITIES)
        return
    }

    ok = true
    return
}


archetype_add_entity_component_data :: proc(scene: ^Scene, archetype: ^Archetype, entity_label: string, component_data: []byte) -> (ok: bool) {
    archetype_add_entity_checks(scene, archetype, entity_label) or_return
    if u32(len(component_data)) != archetype.component_info.total_size_per_entity {
        dbg.debug_point(dbg.LogLevel.ERROR, "Component data size mismatch when adding entity", ARCHETYPE_MAX_ENTITIES)
        return
    }

    entity: Entity
    entity.id = scene.n_Entities
    scene.n_Entities += 1

    entity.archetype_column = archetype.n_Entities
    archetype.n_Entities += 1

    // Add component data
    start_of_component: u32 = 0
    for component_info, i in archetype.component_info.component_infos {
        end_of_component := start_of_component + component_info.size
        append_elems(&archetype.components[i], ..component_data[start_of_component:end_of_component])
        start_of_component += component_info.size
    }

    ok = true
    return
}


archetype_add_entity :: proc(scene: ^Scene, archetype: ^Archetype, entity_label: string, component_data: ..ComponentDataUntyped) -> (ok: bool) {
    dbg.debug_point(dbg.LogLevel.INFO, "Adding archetype entity: %s", entity_label)
    archetype_add_entity_checks(scene, archetype, entity_label) or_return

    entity: Entity
    entity.id = scene.n_Entities
    scene.n_Entities += 1

    entity.archetype_column = archetype.n_Entities
    archetype.n_Entities += 1
    archetype.entities[entity_label] = entity

    for data in component_data {
        comp_index, component_exists := archetype.components_label_match[data.label]
        if !component_exists {
            dbg.debug_point(dbg.LogLevel.ERROR, "Component could not be found")
            return
        }

        dbg.debug_point(dbg.LogLevel.INFO, "Data before serialize: %#v", data)
        serialized_component := component_serialize_new(data)
        dbg.debug_point(dbg.LogLevel.INFO, "Data after serialize: %#v", serialized_component)

        append_elems(&archetype.components[comp_index], ..serialized_component.data)
    }

    ok = true
    return
}


Camera :: struct {
    position: glm.vec3,
    towards: glm.vec3,
    up: glm.vec3,
    look_at: glm.mat4,
    field_of_view: f32,
    aspect_ratio: f32,
    near_plane: f32,
    far_plane: f32
}


scene_add_camera :: proc(scene: ^Scene, camera: Camera) {
    append(&scene.cameras, camera)
    if len(scene.cameras) == 1 do scene.viewpoint = &scene.cameras[0]
}


scene_remove_camera :: proc(scene: ^Scene, camera_index: int) -> (ok: bool) {
    if camera_index < 0 || camera_index >= len(scene.cameras) {
        dbg.debug_point(dbg.LogLevel.ERROR, "Camera index out of range")
        return
    }
    if scene.viewpoint == &scene.cameras[camera_index] {
    // Replace viewpoint

        i: int
        for i = 0; i < len(scene.cameras); i += 1 {
            if i != camera_index {
                scene.viewpoint = &scene.cameras[i]
                break
            }
        }
        if i == len(scene.cameras) {
            dbg.debug_point(dbg.LogLevel.ERROR, "No camera to replace as scene viewpoint")
            return
        }
    }

    // todo Remove camera at index

    ok = true
    return
}