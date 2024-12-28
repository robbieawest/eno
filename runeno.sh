#!/bin/bash

build=false
run=false
testing=false
dbg=false
memory_tracking=true

executable_suffix=""
if [ "$OSTYPE" = "cygwin" ] || [ "$OSTYPE" = "msys" ]; then
  executable_suffix=".exe"
fi

usage() {
    echo "Usage: runeno.sh [
    -b (odin build), 
    -r (odin run), 
    -t (odin test),
    -m (enable memory tracking for testing),
    -d (include debugging symbols), 
    -p (build subpackage instead of the whole of eno, example: ./runeno.sh -p ecs)
    ]"
    exit 0
}

build_options=""
subproj_override=""
while getopts brtmdhp: opt; do
    case "${opt}" in
        b) 
            build=true
            run=false
            ;;
        r) 
            run=true
            build=false
            testing=false
            ;;
        t)
            testing=true
            run=false
            ;;
        m)
            memory_tracking=false
            ;;
        d) 
            dbg=true
            ;;
        p)
            subproj_override=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done

#if [ "$subproj_override" != "" ]; then
#    subproj_override="$subproj_override"
#fi

out_name="-out:bin/eno-$subproj_override"
debug_options=""
test_options=""
build_mode=""

if [ "$build" == true ]; then
    build_options="build"
    out_name="$out_name-build"
fi
if [ "$testing" == true ]; then
  echo "testing"
    if [ "$build" == true ]; then
        build_mode="-build-mode:test"
    else
        build_options="test"
    fi
    
    out_name="$out_name-test"
    test_options="-define:ODIN_TEST_FANCY=true"
    if [ "$memory_tracking" == false ]; then
        test_options="$test_options -define:ODIN_TEST_TRACK_MEMORY=false"
    fi
fi
if [ "$run" == true ]; then
    build_options="run"
    out_name="$out_name-run"
fi
if [ "$dbg" == true ]; then
    out_name="$out_name-debug"
    debug_options="-debug"
fi

out_name="$out_name$executable_suffix"

build_options="$build_options ./src/eno/$subproj_override $out_name $debug_options $test_options $build_mode"
echo $build_options
odin $build_options

exit 0
