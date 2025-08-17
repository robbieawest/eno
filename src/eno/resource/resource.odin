package resource

import dbg "../debug"
import "../utils"
import "../standards"

import "core:slice"
import "core:hash"
import "core:mem"
import "core:log"
import "core:container/intrusive/list"
import "base:runtime"
import "core:math/rand"

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
hash_resource :: proc(resource: $T, allocator: mem.Allocator) -> ResourceHash {
    // Extend possible to give different hash routine for a different resource type
    resource := resource
    when  T == Texture {
        // Does not hash name, image pixel data or the gpu texture
        // If for some reason this needs to be different, don't use hash_resource and instead provide a hash or a hash func
        bytes := make([dynamic]byte, allocator=allocator)
        defer delete(bytes)

        append_elems(&bytes, ..utils.to_bytes(&resource.type))
        utils.map_to_bytes(resource.properties, &bytes)

        append_elems(&bytes, ..utils.to_bytes(&resource.image.w))
        append_elems(&bytes, ..utils.to_bytes(&resource.image.h))
        append_elems(&bytes, ..(transmute([]u8)resource.image.uri))

        return hash_ptr(&resource)
    }
    else when T == ShaderProgram {
        bytes := make([dynamic]byte, allocator=allocator)
        defer delete(bytes)

        utils.map_to_bytes(resource.shaders, &bytes)

        return hash_raw(bytes[:])
    }
    else when T == Shader {
        hashable: struct{ type: ShaderType, source: ShaderSource }
        hashable = { resource.type, resource.source }
        return hash_ptr(&hashable)
    }
    else when T == MaterialType {
        if resource.unique do return rand.uint64()  // If theres a collision out of all 2^64 - 1 possibilities then all I can do is apologize

        hashable: struct{ properties: MaterialPropertyInfos,  double_sided: bool, unlit: bool }
        hashable = { properties=resource.properties, double_sided=resource.double_sided, unlit=resource.unlit }
        return hash_ptr(&hashable)
    }
    else when T == VertexLayout {
        if resource.unique do return rand.uint64()

        return hash_slice(resource.infos)
    }
    else {
        #panic("Type is invalid in hash")
    }
}

@(private)
hash_ptr :: proc(ptr: ^$T) -> ResourceHash {
    return hash.fnv64a(utils.to_bytes(ptr))
}

@(private)
hash_slice :: proc(slice: $T/[]$E) -> ResourceHash {
    raw_slice := transmute(runtime.Raw_Slice)slice
    return hash.fnv64a(transmute([]byte)runtime.Raw_Slice{raw_slice.data, type_info_of(E).size * len(slice)})
}

@(private)
hash_raw :: proc(bytes: []byte) -> ResourceHash {
    return hash.fnv64a(bytes)
}


// Only add/delete resources via the given procedures
ResourceManager :: struct {
    materials: ResourceMapping,
    passes: ResourceMapping,
    shaders: ResourceMapping,
    textures: ResourceMapping,
    vertex_layouts: ResourceMapping,
    billboard_shader: ResourceID,  // Hacky, a proper MaterialType would fix this
    // (later) - not just hacky, it breaks reference counting
    billboard_id: ResourceID,  // Texture
    allocator: mem.Allocator
}

init_resource_manager :: proc(allocator := context.allocator) -> ResourceManager {
    return ResourceManager {
        make(ResourceMapping, allocator=allocator),
        make(ResourceMapping, allocator=allocator),
        make(ResourceMapping, allocator=allocator),
        make(ResourceMapping, allocator=allocator),
        make(ResourceMapping, allocator=allocator),
        nil,
        nil,
        allocator
    }
}


@(private)
compare_resources :: proc(a: $T, b: T) -> bool {

    when T == Texture {
        return utils.equals(a, b)
    }
    else when T == ShaderProgram {
        if len(a.shaders) != len(b.shaders) do return false
        for type, ident in a.shaders {
            if type not_in b.shaders do return false
            if !utils.equals(ident, b.shaders[type]) do return false
        }
        return true
    }
    else when T == Shader {
        // Not a faithful deep compare
        comparable :: struct{ type: ShaderType, source: ShaderSource }
        a_comp := comparable{ a.type, a.source }
        b_comp := comparable{ b.type, b.source }
        return utils.equals(a_comp, b_comp)
    }
    else when T == MaterialType {
        comparable :: struct{ properties: MaterialPropertyInfos, double_sided: bool, unlit: bool, unique: bool }
        a_comp := comparable{ a.properties, a.double_sided, a.unlit, a.unique }
        b_comp := comparable{ b.properties, b.double_sided, b.unlit, b.unique }
        return utils.equals(a_comp, b_comp)
    }
    else when T == VertexLayout {
        return slice.equal(a.infos, b.infos)
    }
    else {
        #panic("Type is invalid in hash")
    }

}


// Assumes resource appears at most once in bucket
// O(N * M) linear + mem compare, M = bytes in T, N = length of bucket
// Linear memory compare as opposed to pointer compare
@(private)
traverse_bucket :: proc(bucket: list.List, resource: $T) -> (node: ^ResourceNode(T), ok: bool) {
    iterator := list.iterator_head(bucket, ResourceNode(T), "node")

    for resource_node in list.iterate_next(&iterator) {
        if compare_resources(resource, resource_node.resource) do return resource_node, true
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

    hash := hash_resource(resource, allocator)

    // Reused code, could be improved but kiss
    if hash in mapping {
        bucket: ^list.List = &mapping[hash]
        resource_node, node_exists := traverse_bucket(bucket^, resource)

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
            id.node = uintptr(node)
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
        dbg.log(.ERROR, "Ident hash not found in mapping, hash: %d, type: %v", ident.hash, typeid_of(T))
        return
    }

    bucket := &mapping[ident.hash]
    resource_node, resource_exists := traverse_bucket_ptr(bucket^, T, ident.node)

    if !resource_exists {
        dbg.log(.ERROR, "Resource could not be found")
        return
    }

    if resource_node.reference_count >= 1 {
        dbg.log(.INFO, "Decreasing reference count of resource of type: %v", typeid_of(T))
        resource_node.reference_count -= 1
    }
    else {
        dbg.log(.INFO, "Deleting resource of type: %v", typeid_of(T))
        list.remove(bucket, &resource_node.node)
        free(resource_node, allocator)

        if bucket.head == nil || bucket.tail == nil {
            delete_key(mapping, ident.hash)
        }
    }

    return true
}

@(private)
get_resource :: proc(
    mapping: ^ResourceMapping,
    $T: typeid,
    ident: ResourceIdent,
    is_shared_reference := false,
    loc := #caller_location
) -> (resource: ^T, ok: bool) {
    if ident.hash not_in mapping {
        dbg.log(.ERROR, "Ident hash not found in mapping, hash: %d, type: %v", ident.hash, typeid_of(T), loc=loc)
        return
    }

    bucket := mapping[ident.hash]
    resource_node, node_found := traverse_bucket_ptr(bucket, T, ident.node)
    if !node_found {
        dbg.log(.ERROR, "Node not found in bucket, hash: %d, node: %p, type: %v", ident.hash, rawptr(ident.node), typeid_of(T), loc=loc)
        dbg.log(.ERROR, "Mapping: %#v", mapping, loc=loc)
        return
    }

    if is_shared_reference do resource_node.reference_count += 1

    return &resource_node.resource, true
}


// Allocates buf for pointers - recommend specifying temp allocator
@(private)
get_resources :: proc(mapping: ResourceMapping, $T: typeid, allocator := context.allocator) -> []^T {
    resources := make([dynamic]^T, allocator)

    for _, bucket in mapping {
        iterator := list.iterator_head(bucket, ResourceNode(T), "node")
        for resource_node in list.iterate_next(&iterator) {
            append(&resources, &resource_node.resource)
        }
    }

    return resources[:]
}

get_materials :: proc(manager: ResourceManager, allocator := context.allocator) -> []^MaterialType {
    return get_resources(manager.materials, MaterialType, allocator)
}

get_vertex_layouts :: proc(manager: ResourceManager, allocator := context.allocator) -> []^VertexLayout {
    return get_resources(manager.vertex_layouts, VertexLayout, allocator)
}

add_texture :: proc(manager: ^ResourceManager, texture: Texture) -> (id: ResourceIdent, ok: bool) {
    return add_resource(&manager.textures, Texture, texture, manager.allocator)
}

add_shader_pass :: proc(manager: ^ResourceManager, program: ShaderProgram) -> (id: ResourceIdent, ok: bool) {
    return add_resource(&manager.passes, ShaderProgram, program, manager.allocator)
}

add_shader :: proc(manager: ^ResourceManager, program: Shader) -> (id: ResourceIdent, ok: bool) {
    return add_resource(&manager.shaders, Shader, program, manager.allocator)
}

add_material :: proc(manager: ^ResourceManager, material: MaterialType) -> (id: ResourceIdent, ok: bool) {
    return add_resource(&manager.materials, MaterialType, material, manager.allocator)
}

add_vertex_layout :: proc(manager: ^ResourceManager, layout: VertexLayout) -> (id: ResourceIdent, ok: bool) {
    return add_resource(&manager.vertex_layouts, VertexLayout, layout, manager.allocator)
}

get_texture :: proc(manager: ^ResourceManager, id: ResourceID) -> (texture: ^Texture, ok: bool) {
    return get_resource(&manager.textures, Texture, utils.unwrap_maybe(id) or_return)
}

get_material :: proc(manager: ^ResourceManager, id: ResourceID) -> (material: ^MaterialType, ok: bool) {
    return get_resource(&manager.materials, MaterialType, utils.unwrap_maybe(id) or_return)
}

get_shader_pass :: proc(manager: ^ResourceManager, id: ResourceID) -> (program: ^ShaderProgram, ok: bool) {
    return get_resource(&manager.passes, ShaderProgram, utils.unwrap_maybe(id) or_return)
}

get_shader :: proc(manager: ^ResourceManager, id: ResourceID) -> (program: ^Shader, ok: bool) {
    return get_resource(&manager.shaders, Shader, utils.unwrap_maybe(id) or_return)
}

get_vertex_layout :: proc(manager: ^ResourceManager, id: ResourceID, loc := #caller_location) -> (layout: ^VertexLayout, ok: bool) {
    return get_resource(&manager.vertex_layouts, VertexLayout, utils.unwrap_maybe(id) or_return, loc=loc)
}

remove_texture :: proc(manager: ^ResourceManager, id: ResourceID) -> (ok: bool) {
    return remove_resource(&manager.textures, Texture, utils.unwrap_maybe(id) or_return, manager.allocator)
}

remove_material :: proc(manager: ^ResourceManager, id: ResourceID) -> (ok: bool) {
    return remove_resource(&manager.materials, MaterialType, utils.unwrap_maybe(id) or_return, manager.allocator)
}

remove_shader_pass :: proc(manager: ^ResourceManager, id: ResourceID) -> (ok: bool) {
    return remove_resource(&manager.passes, ShaderProgram, utils.unwrap_maybe(id) or_return, manager.allocator)
}

remove_shader :: proc(manager: ^ResourceManager, id: ResourceID) -> (ok: bool) {
    return remove_resource(&manager.shaders, Shader, utils.unwrap_maybe(id) or_return, manager.allocator)
}

remove_layout :: proc(manager: ^ResourceManager, id: ResourceID) -> (ok: bool) {
    return remove_resource(&manager.vertex_layouts, VertexLayout, utils.unwrap_maybe(id) or_return, manager.allocator)
}


// estupido
get_billboard_lighting_shader :: proc(manager: ^ResourceManager) -> (result: ResourceIdent, ok: bool) {

    ident, shader_ok := manager.billboard_shader.?
    billboard_shader: ^ShaderProgram
    if shader_ok do billboard_shader, ok = get_resource(&manager.passes, ShaderProgram, ident, is_shared_reference=true)

    if !shader_ok {
        program := read_shader_source(manager, standards.SHADER_RESOURCE_PATH + "billboard.vert", standards.SHADER_RESOURCE_PATH + "billboard.frag") or_return
        manager.billboard_shader = result
        return result, true
    }
    return ident, true
}


// Allocator for internal temp uses - not for freeing resources, this uses manager.allocator
clear_unused_resources :: proc(manager: ^ResourceManager, allocator := context.temp_allocator) ->  (ok: bool) {
    ok = true
    ok &= clear(manager, &manager.materials, MaterialType, manager.allocator, allocator, check_reference_zero(MaterialType))
    ok &= clear(manager, &manager.textures, Texture, manager.allocator, allocator, check_reference_zero(Texture))
    ok &= clear(manager, &manager.passes, ShaderProgram, manager.allocator, allocator, check_reference_zero(ShaderProgram))
    return
}

@(private)
check_reference_zero :: proc($T: typeid) -> proc(R: ResourceNode(T)) -> bool {
    return proc(resource: ResourceNode(T)) -> bool {
        return resource.reference_count == 0
    }
}

// Each resource type must not also delete a resource of the same type or it will be icky and potentially breaking
// Does not clean up GPU resource, do this with render package
destroy_manager :: proc(manager: ^ResourceManager, allocator := context.temp_allocator) -> (ok: bool) {
    dbg.log(.INFO, "Destroying manager")
    ok = true
    ok &= clear(manager, &manager.materials, MaterialType, manager.allocator, allocator, nil)
    ok &= clear(manager, &manager.textures, Texture, manager.allocator, allocator, nil)
    ok &= clear(manager, &manager.passes, ShaderProgram, manager.allocator, allocator, nil)

    delete(manager.materials)
    delete(manager.textures)
    delete(manager.passes)
    return
}

@(private)
destroy_resource :: proc(manager: ^ResourceManager, resource: ^$T) -> (ok: bool){
    when T == Texture {
        destroy_texture(resource)
    }
    else when T == ShaderProgram {
        destroy_shader_program(manager, resource^) or_return
    }
    else when T == MaterialType {
        destroy_material_type(manager, resource^) or_return
    }
    else when T == VertexLayout {
        destroy_vertex_layout(manager, resource^) or_return
    }
    return true
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
    if clear_by == nil do dbg.log(.INFO, "Fully clearing mapping of type: %v", typeid_of(T))

    clear_proc, clear_proc_ok := clear_by.?

    for hash, &bucket in mapping {
        if bucket.head == nil || bucket.tail == nil {
            delete_key(mapping, hash)
            continue
        }

        iterator := list.iterator_head(bucket, ResourceNode(T), "node")
        node := bucket.head
        for node != nil {
            resource_node := (^ResourceNode(T))(uintptr(node) - iterator.offset)
            if !clear_proc_ok || clear_proc(resource_node^) {
                // Delete
                dbg.log(.INFO, "Deleting node of type: %v", typeid_of(T))
                list.remove(&bucket, &resource_node.node)

                destroy_ok := destroy_resource(manager, &resource_node.resource) // Could potentially delete a node in bucket
                if !destroy_ok {
                    dbg.log(.ERROR, "Destruction of resource of type: %v failed", typeid_of(T))
                    return
                }

                node = node.next
                alloc_err := free(resource_node, allocator)
                if alloc_err != .None {
                    dbg.log(.ERROR, "Allocator error while freeing resource of type: %v", typeid_of(T), loc=loc)
                    return
                }
            }
            else do node = node.next
        }

    }

    return true
}

