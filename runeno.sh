#!/bin/bash

build=true
run=false
testing=false
dbg=false

usage() {
    echo "Usage: srceno [
    -b (odin build), 
    -r (odin run), 
    -t (odin test), 
    -d (include debugging symbols), 
    -p (build subpackage instead of the whole of eno, example: ./srceno.sh -p ecs)
    ]"
    exit 0
}

build_options=""
subproj_override=""
while getopts brtdhp: opt; do
    case "${opt}" in
        b) 
            build=true
            testing=false
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
            build=false
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

if [ "$build" == true ]; then
    build_options="build"
    out_name="$out_name-build"
fi
if [ "$run" == true ]; then
    build_options="run"
    out_name="$out_name-run"
fi
if [ "$testing" == true ]; then
    build_options="test"
    out_name="$out_name-test"
    test_options="-define:ODIN_TEST_FANCY=true"
fi
if [ "$dbg" == true ]; then
    out_name="$out_name-debug"
    debug_options="-debug"
fi

build_options="$build_options ./src/eno/$subproj_override $out_name $debug_options $test_options"

odin $build_options

exit 0
