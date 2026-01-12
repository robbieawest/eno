# eno
game engine WIP written in odin

This game engine has been developed primarily for learning purposes. Writing this semi-large project (~15K lines) has made much clear to me, including many common and open problems in game engine design. 
The engine focuses on providing a simple and relatively powerful game engine interface for programmers to interact with, and it attempts to be interactive and extensible in every stage.

## Renderer output examples

Indirect Environment Lighting <br> Including ambient and specular occlusion        |  Direct lighting
:-------------------------:|:-------------------------:
<img src="https://github.com/robbieawest/eno/blob/main/demo-images/metro_so.png" alt="" width="722" height="540">  |  <img src="https://github.com/robbieawest/eno/blob/main/demo-images/direct.png" alt="" width="722" height="540">

Clearcoat test <br> Left: Fully reflective &emsp; Middle: Rough &emsp; Right: Same as rough middle but with a second reflective layer, requiring multiple reflectance evaluations with energy conservation
:--------------------------------------------------:
<img src="https://github.com/robbieawest/eno/blob/main/demo-images/clearcoat_test.png" alt="" width="1400" height="540">

Sponza
:--------------------------------------------------:
<img src="https://github.com/robbieawest/eno/blob/main/demo-images/Sponza.png" alt="" width="1400" height="540">



## Building instructions

#### Prerequisites
- `odin` programming language is installed, the current tested release is `dev-2025-09:42c2cb89b`.
- A modern `OpenGL` version is installed (at least 4.3).

If you wish to build eno, you can do:

1. Build the demo directly using `odin`
```
odin build ./src/eno/demo -out:bin/eno-build
```
, adding `.exe` on windows, and provided `bin/` exists.


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

## Technical Features and scope
A list of features detailing what eno currently implements:

- Windowing using SDL2 ( `window` package )
- Archetypal Entity Component System with a powerful query interface where entity component data is stored tighly packed ( `ecs` package )
- GLTF model/scene loading with PBR material support ( `resource` package -> `gltf.odin` ). There is an issue with loading certain models which I haven't gotten around to fixing yet
- Controls using a centralized hook structure ( `control` package )
- OpenGL renderer backend ( `render` package )
- Physically based rendering workflow supporting normal mapping, all glTF standard PBR materials, and the KHR_Clearcoat and KHR_Specular extensions
- Central resource manager with hashing and reference counting to share/store shaders, material permutations, vertex layout permuations etc. ( `resource` package )
- Liberal render pass interface with a general `render` handler
- Image based environment indirect lighting - supporting physically based rendering, taking incoming light from a preloaded image environment (and precomputed BRDF components)
- Dear Imgui integration, with a UI element interface to create UI elements or use those available
- Ambient occlusion calculated in screen space (SSAO), with runtime bent normal calculation. Bent normals follow the [Klehm2011](https://www.researchgate.net/publication/220839265_Bent_Normals_and_Cones_in_Screen-space) bent cones description, and are packed with the occlusion term. A seperated cross bilteral filter is then done to remove noise while preserving edges and the cone variance in the bent normals
- Specular occlusion using the bent cone variance and bent normal from the SSAO pass. This follows the [Jimenez2016](https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf) specular occlusion (cone-cone approximation) term, using the solution given in Ambient Aperture Lighting [Oat2006](https://dl.acm.org/doi/10.1145/1185657.1185833). This has limitations when using SSAO for the occlusion and bent normal calculation, as the (very typical and expected) SSAO artifacts are exacerbated.

What I'm working on:
- UI improvements, including resource inspection and a scene hierarchy

Things I'd like to implement if I have the time:
- Clustered forward rendering to support a large amount of lights on the screen
- Pre-render geometry processing for tangent approximations with `mikkt`; an unweld -> `mikkt` tangent generation -> weld process

Far reaching:
- Vulkan backend
- MoltenVK for Mac


## Development and the code

The demo files provide an idea of how the engine could be interacted with by a programmer, this includes the usage of `before_frame` and `after_frame` function ptrs, configuration of controls, addition of ui elements, etc.

Game engines are complex layers of abstraction, often sacrificing user(developer) control in the development of internal systems or outwards functionality. To balance extensibility, developer control, and simplicity, I've opted to give internal functionality within layered abstractions. This means that the developer can choose the layer of abstraction they wish to work with, and that this is supported as defined behaviour by the source. Rendering for example has a render pass and pipelining interface which gives direct control of what is rendered in the central `render` procedure, but is heavy to configure. As such it has a facade which exposes existing implementations of SSAO, G-Buffer setup etc. The UI also instead of having a set UI like most engines exposes a UI element interface with some obvious UI elements provided. Developers have the ability to implement their own UI elements, potentially taking reference from the existing UI elements.

Most of the engine (at least recent changes) attempts to follow this idea, improving the usability despite the engine being smaller.
