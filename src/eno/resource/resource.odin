package resource

import "../shader"
import dbg "../debug"
import "../utils"

import "core:hash"
import "core:mem"
import "core:log"
import "core:container/intrusive/list"
import standards "../standards"
import runtime "base:runtime"

// Package defining the resource manager and relevant systems relating to it

// Nullable, just a Maybe(struct{ .. })
ResourceIdent :: struct {
    hash: ResourceHash,
    node: ResourceNodeID
}
ResourceID :: Maybe(ResourceIdent)

ResourceNodeID :: uintptr  // To avoid dereferencing - this is just an index which will always point to the correct node
ResourceHash :: u64

ResourceBucket :: list.List
ResourceNode :: struct($T: typeid) {
    node: list.Node,
    resource: T,
    reference_count: u32
}

ResourceMapping :: map[ResourceHash]ResourceBucket

@(private)
hash_resource :: proc($T: typeid, resource: T) -> ResourceHash {
    // Extend possible to give different hash routine for a different resource type
    when T == shader.ShaderProgram || T == Texture || T == Material {
        resource := resource
        return hash.fnv64a(transmute([]byte)runtime.Raw_Slice{ &resource, type_info_of(T).size })
    }
    else {
        #panic("Type is invalid in hash")
    }
}

// Only add/delete resources via the given procedures
ResourceManager :: struct {
    materials: ResourceMapping,
    shaders: ResourceMapping,
    textures: ResourceMapping,
    billboard_shader: ResourceID,  // Hacky, a proper MaterialType would fix this
    billboard_id: ResourceID,  // Texture
    allocator: mem.Allocator
}

init_resource_manager :: proc(allocator := context.allocator) -> ResourceManager {
    return ResourceManager {
        make(ResourceMapping, allocator=allocator),
        make(ResourceMapping, allocator=allocator),
        make(ResourceMapping, allocator=allocator),
        nil,
        nil,
        allocator
    }
}

// Allocates buf for material pointers - recommend specifying temp allocator
get_materials :: proc(manager: ResourceManager, allocator := context.allocator) -> []^Material {
    mat_dyn := make([dynamic]^Material, allocator)

    for _, bucket in manager.materials {
        iterator := list.iterator_head(bucket, ResourceNode(Material), "node")
        for resource_node in list.iterate_next(&iterator) {
            append(&mat_dyn, &resource_node.resource)
        }
    }

    return mat_dyn[:]
}

// Assumes resource appears at most once in bucket
// O(N * M) linear + mem compare, M = bytes in T, N = length of bucket
// Linear memory compare as opposed to pointer compare
@(private)
traverse_bucket :: proc(bucket: list.List, $T: typeid, resource: T) -> (node: ^ResourceNode(T), ok: bool) {
    iterator := list.iterator_head(bucket, ResourceNode(T), "node")

    for resource_node in list.iterate_next(&iterator) {
        if utils.equals(resource, resource_node.resource) do return resource_node, true
    }

    return
}

// O(N) linear + pointer compare
@(private)
traverse_bucket_ptr :: proc(bucket: list.List, $T: typeid, ptr: uintptr) -> (node: ^ResourceNode(T), ok: bool) {
    iterator := list.iterator_head(bucket, ResourceNode(T), "node")

    for resource_node in list.iterate_next(&iterator) {
        if ptr == uintptr(resource_node) do return resource_node, true
    }

    return
}

@(private)
add_resource :: proc(
    mapping: ^ResourceMapping,
    $T: typeid,
    resource: T,
    allocator: mem.Allocator
) -> (id: ResourceIdent, ok: bool) {

    hash := hash_resource(T, resource)

    // Reused code, could be improved but kiss
    if hash in mapping {
        bucket: ^list.List = &mapping[hash]
        resource_node, node_exists := traverse_bucket(bucket^, T, resource)

        if node_exists {
            dbg.log(.INFO, "Increasing reference of resource, hash: %d", hash)
            // References an existing node/resource which is the same
            // Now, increase reference count of that resource and return an ident

            if resource_node.reference_count == max(u32) {
                dbg.log(.ERROR, "Max reference count")
                return
            }
            resource_node.reference_count += 1
            id.hash = hash
            id.node = uintptr(resource_node)
        }
        else {
            dbg.log(.INFO, "Hash found, adding new node in resource bucket of type: %v", typeid_of(T))
            node := new(ResourceNode(T), allocator=allocator)
            node.resource = resource
            node.reference_count = 1

            list.push_back(bucket, &node.node)
            dbg.log(.INFO, "Added new node in bucket of hash: %d", hash)

            id.hash = hash
            id.node = uintptr(&node)
        }
    }
    else {
        dbg.log(.INFO, "Hash not found, adding new node in new resource bucket of type: %v", typeid_of(T))
        new_list: list.List
        node := new(ResourceNode(T), allocator=allocator)
        node.resource = resource
        node.reference_count = 1

        list.push_back(&new_list, &node.node)
        mapping[hash] = new_list
        dbg.log(.INFO, "Added new mapping of hash: %d", hash)

        id.hash = hash
        id.node = uintptr(node)
    }

    ok = true
    return
}

// Does not necessarily free up memory since this uses reference counting
@(private)
remove_resource :: proc(
    mapping: ^ResourceMapping,
    $T: typeid,
    ident: ResourceIdent,
    allocator: mem.Allocator
) -> (ok: bool) {
    if ident.hash not_in mapping {
        dbg.log(.ERROR, "Ident hash not found in mapping")
        return
    }

    bucket := mapping[ident.hash]
    resource_node, resource_exists := traverse_bucket_ptr(bucket, T, ident.node)

    if !resource_exists {
        dbg.log(.ERROR, "Resource could not be found")
        return
    }

    if resource_node.reference_count > 1 do resource_node.reference_count -= 1
    else {
        list.remove(&bucket, &resource_node.node)
        free(resource_node, allocator)
    }

    return true
}

@(private)
get_resource :: proc(
    mapping: ^ResourceMapping,
    $T: typeid,
    ident: ResourceIdent,
    loc := #caller_location
) -> (resource: ^T, ok: bool) {
    if ident.hash not_in mapping {
        dbg.log(.ERROR, "Ident hash not found in mapping")
        return
    }

    bucket := mapping[ident.hash]
    resource_node, node_found := traverse_bucket_ptr(bucket, T, ident.node)
    if !node_found {
        dbg.log(.ERROR, "Node not found in bucket, hash: %d, node: %p, type: %v", ident.hash, rawptr(ident.node), typeid_of(T))
        dbg.log(.ERROR, "Mapping: %#v", mapping)
        return
    }

    return &resource_node.resource, true
}

add_texture :: proc(manager: ^ResourceManager, texture: Texture) -> (id: ResourceIdent, ok: bool) {
    return add_resource(&manager.textures, Texture, texture, manager.allocator)
}

add_shader :: proc(manager: ^ResourceManager, program: shader.ShaderProgram) -> (id: ResourceIdent, ok: bool) {
    return add_resource(&manager.shaders, shader.ShaderProgram, program, manager.allocator)
}

add_material :: proc(manager: ^ResourceManager, material: Material) -> (id: ResourceIdent, ok: bool) {
    return add_resource(&manager.materials, Material, material, manager.allocator)
}

get_texture :: proc(manager: ^ResourceManager, id: ResourceID) -> (texture: ^Texture, ok: bool) {
    return get_resource(&manager.textures, Texture, utils.unwrap_maybe(id) or_return)
}

get_material :: proc(manager: ^ResourceManager, id: ResourceID) -> (material: ^Material, ok: bool) {
    return get_resource(&manager.materials, Material, utils.unwrap_maybe(id) or_return)
}

get_shader :: proc(manager: ^ResourceManager, id: ResourceID) -> (program: ^shader.ShaderProgram, ok: bool) {
    return get_resource(&manager.shaders, shader.ShaderProgram, utils.unwrap_maybe(id) or_return)
}

remove_texture :: proc(manager: ^ResourceManager, id: ResourceID) -> (ok: bool) {
    return remove_resource(&manager.textures, Texture, utils.unwrap_maybe(id) or_return, manager.allocator)
}

remove_material :: proc(manager: ^ResourceManager, id: ResourceID) -> (ok: bool) {
    return remove_resource(&manager.materials, Material, utils.unwrap_maybe(id) or_return, manager.allocator)
}

remove_shader :: proc(manager: ^ResourceManager, id: ResourceID) -> (ok: bool) {
    return remove_resource(&manager.shaders, shader.ShaderProgram, utils.unwrap_maybe(id) or_return, manager.allocator)
}


// estupido
get_billboard_lighting_shader :: proc(manager: ^ResourceManager) -> (result: ResourceIdent, ok: bool) {

    shader_ident, shader_ok := manager.billboard_shader.?
    billboard_shader: ^shader.ShaderProgram
    if shader_ok do billboard_shader, shader_ok = get_resource(&manager.shaders, shader.ShaderProgram, shader_ident)

    if !shader_ok {
        program := shader.read_shader_source(standards.SHADER_RESOURCE_PATH + "billboard.vert", standards.SHADER_RESOURCE_PATH + "billboard.frag") or_return
        result = add_shader(manager, program) or_return
        manager.billboard_shader = result
        return result, true
    }
    return shader_ident, true
}


// Allocator for internal temp uses - not for freeing resources, this uses manager.allocator
clear_unused_resources :: proc(manager: ^ResourceManager, allocator := context.temp_allocator) ->  (ok: bool) {
    ok = true
    ok &= clear(manager, &manager.materials, Material, manager.allocator, allocator, check_reference_zero(Material))
    ok &= clear(manager, &manager.textures, Texture, manager.allocator, allocator, check_reference_zero(Texture))
    ok &= clear(manager, &manager.shaders, shader.ShaderProgram, manager.allocator, allocator, check_reference_zero(shader.ShaderProgram))
    return
}

@(private)
check_reference_zero :: proc($T: typeid) -> proc(R: ResourceNode(T)) -> bool {
    return proc(resource: ResourceNode(T)) -> bool {
        return resource.reference_count == 0
    }
}

// Each resource type must not also delete a resource of the same type or it will be icky I think
// Does not clean up GPU resource, do this with render package
destroy_manager :: proc(manager: ^ResourceManager, allocator := context.temp_allocator) -> (ok: bool) {
    ok = true
    ok &= clear(manager, &manager.materials, Material, manager.allocator, allocator, nil)
    ok &= clear(manager, &manager.textures, Texture, manager.allocator, allocator, nil)
    ok &= clear(manager, &manager.shaders, shader.ShaderProgram, manager.allocator, allocator, nil)

    delete(manager.materials)
    delete(manager.textures)
    delete(manager.shaders)
    return
}

destroy_resource :: proc(manager: ^ResourceManager, resource: $T) {
    when T == Texture {
        destroy_texture(resource)
    }
    else when T == shader.ShaderProgram {
        shader.destroy_shader_program(resource)
    }
    else when T == Material {
        destroy_material(manager, resource)
    }
    else {
        #panic("Disallowed resource type")
    }

}

@(private)
clear :: proc(
    manager: ^ResourceManager,
    mapping: ^ResourceMapping,
    $T: typeid,
    allocator: mem.Allocator,
    temp_allocator: mem.Allocator,
    clear_by: Maybe(proc(R: ResourceNode(T)) -> bool),
    loc := #caller_location
) -> (ok: bool) {

    clear_proc, clear_proc_ok := clear_by.?

    for hash, &bucket in mapping {
        if bucket.head == nil || bucket.tail == nil {
            delete_key(mapping, hash)
            continue
        }

        iterator := list.iterator_head(bucket, ResourceNode(T), "node")

        to_remove := make([dynamic]^ResourceNode(T), temp_allocator); defer delete(to_remove)
        for resource_node in list.iterate_next(&iterator) {
            if !clear_proc_ok || clear_proc(resource_node^) {
                append(&to_remove, resource_node)
            }
        }

        for &node in to_remove {
            list.remove(&bucket, &node.node)
            destroy_resource(manager, node.resource)
            alloc_err := free(node, allocator)
            if alloc_err != .None {
                dbg.log(.ERROR, "Allocator error while freeing resource of type: %v", typeid_of(T), loc=loc)
                return
            }
        }
    }

    return true
}

