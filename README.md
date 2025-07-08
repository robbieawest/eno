# eno
game engine WIP written in odin

Focuses on providing a simple and relatively powerful game engine interface for programmers to interact with.
Attempts to be interactable and extendible in every stage.

## Building

#### Prerequisites
- `odin` programming language is installed, the current tested release is `dev-2025-04`.
- `SDL2` is installed.
- `OpenGL` is installed.

If you wish to build eno, you can do:

1. Build directly using `odin`
```
odin build ./src/eno -out:bin/eno-build
./bin/eno-build
```
, swapping out `build` for `run` if you wish to run the program immediately.

2. Use the build script `runeno.sh`.

`./runeno.sh -h` gives the usage, the arguments `-b -r -t -d -p` give functionality on what you are building and how, including testing and debug symbol generation.
```
user@os:../eno$ ./runeno.sh -h
Usage: runeno.sh [
    -b (odin build), 
    -r (odin run), 
    -t (odin test), 
    -m (enable memory tracking for testing),
    -d (include debugging symbols), 
    -p (build subpackage instead of the whole of eno, example: ./runeno.sh -p ecs)
    ]
```
Permissions may have to be updated before running the build script.

* You may need to add SDL2.dll to `bin/`, you can find this in `{odin_dir}/vendor/sdl2`.

## Features and scope
A list of features detailing what eno currently implements:

- Windowing using SDL2
- OpenGL rendering API
- Entity Component System featuring a Scene > Archetype > Entity hierarchical structure, a Component API with component serializatrion/deserialization, and systems for certain batch operations. Implements a cache optimised structure for component data with byte arrays, stored within archetypes. `ecs` package
- GLTF model loading from a scene with cgltf Odin bindings into a Model API in the `model` package
- Dynamic shader generation within the `shader` package
- Controls using a centralized hook structure

Shortly upcoming features:
- Deferred rendering pipeline - integrates everything in the project so far, and changes a lot.
- Some better APIs (particularly for ECS systems)

Eno is made to be cross-platform where possible. I have plans for integrating Vulkan and to be able to target Mac with MoltenVK.
I have certain plans to make an option for GLFW instead of SDL as the windower, however I'd likely focus on other things first as it really does not change anything for anybody.

I've been developing around the renderer for a while now, so eno currently doesn't have much to show in terms of viewable graphics. This is done on purpose, so that I don't have to rewrite the renderer and adjacent systems a million times in the future (Which I still likely will, but hopefully less :)).
