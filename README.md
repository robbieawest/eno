# eno
game engine WIP written in odin

Focuses on providing a simple and relatively powerful game engine interface for programmers to interact with.
Attempts to be interactable and extendible in every stage.

Helmet with IBL, AO + bent normals            |  2
:-------------------------:|:-------------------------:
<img src="https://github.com/robbieawest/eno/blob/main/demo-images/helmet_golden_bay.png" alt="" width="722" height="540">  |  <img src="https://github.com/robbieawest/eno/blob/main/demo-images/helmet_park_stage.png" alt="" width="722" height="540">

Supra with clearcoat, specular extensions            |  Clearcoat test
:-------------------------:|:-------------------------:
<img src="https://github.com/robbieawest/eno/blob/main/demo-images/supra_park_stage.png" alt="" width="722" height="540">  |  <img src="https://github.com/robbieawest/eno/blob/main/demo-images/clearcoat_test.png" alt="" width="722" height="540">




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

- Windowing using SDL2 ( `window` package )
- Archetypal Entity Component System with a powerful query interface where entity component data is stored tighly packed in a cache-efficient manner ( `ecs` package )
- GLTF model/scene loading with full PBR material support ( `resource` package -> `gltf.odin` )
- Dynamic shader source interface ( `shader` package )
- Controls using a centralized hook structure ( `control` package )
- OpenGL renderer backend ( `render` package )
- PBR workflow supporting normal mapping, all GLTF standard PBR materials, and the KHR_Clearcoat and KHR_Specular extensions.
- Central resource manager with hashing and reference counting to share/store shaders, material permutations, vertex layout permuations etc. ( `resource` package )
- Liberal render pass interface with a general `render` handler.
- Image based indirect lighting via environment cubemap, precalculated irradiance, prefilter and brdf lut.
- SSAO
- Bent normals - WIP, current implemention has issues of lack of small-surface normal detail and typical SSAO artifacts being exacerbated in certain models.

Things I'd like to implement if I have the time:
- Shader introspection and shader defines for more clean render managemnet
- Pre-render geometry processing for tangent approximations with `mikkt`; an unweld -> `mikkt` tangent generation -> weld process
- Forward+
- Animation
- Some better UI elements for scenes/resources
- Order independent transparency

Far reaching:
- Some proper global illumination
- Vulkan backend
- MoltenVK for Mac

