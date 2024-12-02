# eno
game engine WIP written in odin

## Building

#### Prerequisites
- `odin` programming language is installed, the tested release is `dev-2024-11`.

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

## Features and scope
A list of features detailing what eno currently implements:

- Windowing using SDL2
- OpenGL rendering API
- Entity Component System featuring a Scene > Archetype > Entity hierarchical structure, a Component API with component serializatrion/deserialization, and systems for certain batch operations. Implements a cache optimised structure for component data with byte arrays, stored within archetypes. `ecs` package
- GLTF model loading from a scene with cgltf Odin bindings into a Model API in the `model` package
- Dynamic shader generation within the `shader` package
- OpenGL rendering utilities
- A WIP renderer

Shortly upcoming features:

- Renderer advancements!

Eno is made to be cross-platform where possible. I have plans to add Vulkan into the rendering utilities (which has forward compatibility for this case), and to be able to target Mac with MoltenVK.
I have certain plans to make an option for GLFW instead of SDL as the windower, however I'd likely focus on other things first as it really does not change anything for any users.

I've been developing around the renderer for a while now, so eno currently doesn't have much to show in terms of viewable graphics. This is done on purpose, so that I don't have to rewrite the renderer and adjacent systems a million times in the future (Which I still likely will, but hopefully less :)).
