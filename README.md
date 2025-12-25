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

Wheel with no AO           |  Wheel with SSAO + Bent Normals
:-------------------------:|:-------------------------:
<img src="https://github.com/robbieawest/eno/blob/main/demo-images/wheel_no_ao.png" alt="" width="722" height="540">  |  <img src="https://github.com/robbieawest/eno/blob/main/demo-images/wheel_with_bn_ao.png" alt="" width="722" height="540">



## Building

#### Prerequisites
- `odin` programming language is installed, the current tested release is `dev-2025-09:42c2cb89b`.
- A modern `OpenGL` version is installed (at least 4.3).

If you wish to build eno, you can do:

1. Build the demo directly using `odin`
```
odin build ./src/eno/demo -out:bin/eno-build
```
, adding `.exe` on windows.


2. Use the build script `runeno.sh`.

`./runeno.sh -h` gives the usage, the arguments `-b -r -t -d -p` give functionality on what you are building and how, including testing and debug symbol generation.
```
hello@hello:../eno$ ./runeno.sh -h
Usage: runeno.sh [
    -b (odin build), 
    -r (odin run), 
    -t (odin test), 
    -m (enable memory tracking for testing),
    -d (include debugging symbols), 
    -p (build subpackage instead of the whole of eno, example: ./runeno.sh -p ecs)
    ]
```

`runeno.sh -r -p demo` will run the demo.

`SDL2.dll` (Windows) / `SDL2.lib` may need to be added to `bin/` (or the location of your binary), these can be obtained from `{odin installation dir}/vendor/sdl2`.


### Demo

- When running the demo, the UI will open which may be behind the main window
- WASD controls are availabile, with cntrl -> down, space -> up, and m -> disable/enable mouse cursor

## Features and scope
A list of features detailing what eno currently implements:

- Windowing using SDL2 ( `window` package )
- Archetypal Entity Component System with a powerful query interface where entity component data is stored tighly packed ( `ecs` package )
- GLTF model/scene loading with PBR material support ( `resource` package -> `gltf.odin` ). There is an issue with loading certain models which I haven't gotten around to fixing yet
- Controls using a centralized hook structure ( `control` package )
- OpenGL renderer backend ( `render` package )
- PBR workflow supporting normal mapping, all glTF standard PBR materials, and the KHR_Clearcoat and KHR_Specular extensions
- Central resource manager with hashing and reference counting to share/store shaders, material permutations, vertex layout permuations etc. ( `resource` package )
- Liberal render pass interface with a general `render` handler
- Image based indirect lighting via environment cubemap, precalculated irradiance, prefilter and brdf lut
- Dear Imgui integration, with a UI element interface to create UI elements or use those available
- SSAO + Bent normals for irradiance sampling - still need to include bent cone variance in the normals

What I'm working on:
- SSAO/BN shader improvements
- Cross bilateral filtering for SSAO/BNs
- More advanced ambient and specular occlusion, looking at the Jimenez GTAO paper, and at relevant visibility bitmask usage (https://doi.org/10.48550/arXiv.2301.11376)
- UI improvements, maybe elements for visual resource inspection, or a scene hierarchy

Things I'd like to implement if I have the time:
- Pre-render geometry processing for tangent approximations with `mikkt`; an unweld -> `mikkt` tangent generation -> weld process
- Forward+
- Indirect/global illumination

Far reaching:
- Vulkan backend
- MoltenVK for Mac


## Development and the code

The demo files provide an idea of how the engine could be interacted with by a programmer, this includes the usage of `before_frame` and `after_frame` function ptrs, configuration of controls, addition of ui elements, etc.

Game engines are complex layers of abstraction, often sacrificing user(developer) control in the development of internal systems or outwards functionality. To balance extensibility, developer control, and simplicity, I've opted to give internal functionality within layered abstractions. This means that the developer can choose the layer of abstraction they wish to work with, and that this is supported as defined behaviour by the source. Rendering for example has a render pass and pipelining interface which gives direct control of what is rendered in the central `render` procedure, but is heavy to configure. As such it has a facade which exposes existing implementations of SSAO, G-Buffer setup etc. The UI also instead of having a set UI like most engines exposes a UI element interface with some obvious UI elements provided. Developers have the ability to implement their own UI elements, potentially taking reference from the existing UI elements.

Most of the engine (at least recent changes) attempts to follow this idea, improving the usability despite the engine being smaller.
