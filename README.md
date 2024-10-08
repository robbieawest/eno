# eno
game engine WIP written in odin

## Building

#### Prerequisites
- `odin` programming language is installed, the tested release is `dev-2024-08`.

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
    -p (build subpackage instead of the whole of eno, example: ./srceno.sh -p ecs)
    ]
```
You may have to call `chmod +x ./runeno.sh` to update permissions before running the script, on operating systems other than Linux this may differ.
