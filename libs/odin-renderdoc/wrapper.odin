package renderdoc

import "core:dynlib"
import "core:log"
import "core:c"
import "core:math"
import "core:path/filepath"
import "core:os"

LOAD_RENDERDOC :: #config(LOAD_RENDERDOC, true)

when ODIN_OS == .Linux {
	RENDERDOC_DEFAULT_INSTALL_ROOT :: "~/.local/share/applications/renderdoc/lib"
	RENDERDOC_LIB_NAME :: "librenderdoc.so"
}
else {
	RENDERDOC_DEFAULT_INSTALL_ROOT :: "C:/Program Files/RenderDoc"
	RENDERDOC_LIB_NAME :: "renderdoc.dll"
}

// utility to load renderdoc, pass in the path to renderdoc if not installed at the default path
load_api :: proc(renderdoc_install_root: string = RENDERDOC_DEFAULT_INSTALL_ROOT, version: Version = .API_Version_1_6_0) -> (lib: dynlib.Library, rdoc_api: rawptr, ok: bool) {
	when LOAD_RENDERDOC {
		dll_path := filepath.join([]string{renderdoc_install_root, RENDERDOC_LIB_NAME}, context.temp_allocator)
		defer delete(dll_path, context.temp_allocator)
	
		if !os.exists(renderdoc_install_root) {
			log.errorf("renderdoc install root %v doesnt exist", renderdoc_install_root)
			return nil, nil, false
		}
	
		rdoc_lib, did_load := dynlib.load_library(dll_path)
		if !did_load {
			log.errorf("could not load %v, reason: %v", dll_path, dynlib.last_error())
			return nil, nil, false
		}
		
		GET_API_SYMBOL :: "RENDERDOC_GetAPI"
		symbol_ptr, found := dynlib.symbol_address(rdoc_lib, GET_API_SYMBOL)
		if !found {
			log.errorf("could not find symbol %v in %v, %v", GET_API_SYMBOL, dll_path, dynlib.last_error())
			return nil, nil, false
		}
	
		GetAPI: GetAPIProc = cast(GetAPIProc) symbol_ptr
		GetAPI(version, &rdoc_api)
		return rdoc_lib, rdoc_api, true
	} else {
		return nil, nil, false
	}
}

// utility to unload renderdoc
@(disabled = !LOAD_RENDERDOC)
unload_api :: proc(lib: dynlib.Library) {
	if lib == nil {
		return
	}

	did_unload := dynlib.unload_library(lib)
	if !did_unload {
		log.errorf("error unloading lib %v, reason: %v", lib, dynlib.last_error())
		return
	}

	log.info("unloaded renderdoc")
}

// Sets an option that controls how RenderDoc behaves on capture.
//
// Returns 1 if the option and value are valid
// Returns 0 if either is invalid and the option is unchanged
SetCaptureOptionU32 :: proc "c" (rdoc_api: rawptr, opt : CaptureOption, val : u32) -> c.int {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.SetCaptureOptionU32(opt, val)
	} else {
		return 0
	}
}

SetCaptureOptionF32 :: proc "c" (rdoc_api: rawptr, opt : CaptureOption, val : f32) -> c.int {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.SetCaptureOptionF32(opt, val)
	} else {
		return 0
	}
}


// Gets the current value of an option as a uint32_t
//
// If the option is invalid, 0xffffffff is returned
GetCaptureOptionU32 :: proc "c" (rdoc_api: rawptr, opt : CaptureOption) -> u32 {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0xffffffff
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.GetCaptureOptionU32(opt)
	} else {
		return 0xffffffff
	}
}

// Gets the current value of an option as a float
//
// If the option is invalid, -FLT_MAX is returned
GetCaptureOptionF32 :: proc "c" (rdoc_api: rawptr, opt : CaptureOption) -> f32 {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return -math.F32_MAX
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.GetCaptureOptionF32(opt)
	} else {
		return -math.F32_MAX
	}
}

// Sets which key or keys can be used to toggle focus between multiple windows
//
// If keys is NULL or num is 0, toggle keys will be disabled
@(disabled = !LOAD_RENDERDOC)
SetFocusToggleKeys :: proc "c" (rdoc_api: rawptr, keys : []InputButton) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.SetFocusToggleKeys(raw_data(keys), cast(i32) len(keys))
}

// Sets which key or keys can be used to capture the next frame
//
// If keys is NULL or num is 0, captures keys will be disabled
@(disabled = !LOAD_RENDERDOC)
SetCaptureKeys :: proc "c" (rdoc_api: rawptr, keys : []InputButton) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.SetCaptureKeys(raw_data(keys), cast(i32) len(keys))
}

// returns the overlay bits that have been set
GetOverlayBits :: proc "c" (rdoc_api: rawptr) -> u32 {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.GetOverlayBits()
	} else {
		return 0
	}
}

// sets the overlay bits with an and & or mask
@(disabled = !LOAD_RENDERDOC)
MaskOverlayBits :: proc "c" (rdoc_api: rawptr, And : u32, Or : u32) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.MaskOverlayBits(And, Or)
}

// this function will attempt to remove RenderDoc's hooks in the application.
//
// Note: that this can only work correctly if done immediately after
// the module is loaded, before any API work happens. RenderDoc will remove its
// injected hooks and shut down. Behaviour is undefined if this is called
// after any API functions have been called, and there is still no guarantee of
// success.
@(disabled = !LOAD_RENDERDOC)
RemoveHooks :: proc "c" (rdoc_api: rawptr) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.RemoveHooks()
}

// This function will unload RenderDoc's crash handler.
//
// If you use your own crash handler and don't want RenderDoc's handler to
// intercede, you can call this function to unload it and any unhandled
// exceptions will pass to the next handler.
@(disabled = !LOAD_RENDERDOC)
UnloadCrashHandler :: proc "c" (rdoc_api: rawptr) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.UnloadCrashHandler()
}

// Sets the capture file path template
//
// pathtemplate is a UTF-8 string that gives a template for how captures will be named
// and where they will be saved.
//
// Any extension is stripped off the path, and captures are saved in the directory
// specified, and named with the filename and the frame number appended. If the
// directory does not exist it will be created, including any parent directories.
//
// If pathtemplate is NULL, the template will remain unchanged
//
// Example:
//
// SetCaptureFilePathTemplate("my_captures/example");
//
// Capture #1 -> my_captures/example_frame123.rdc
// Capture #2 -> my_captures/example_frame456.rdc
@(disabled = !LOAD_RENDERDOC)
SetCaptureFilePathTemplate :: proc "c" (rdoc_api: rawptr, pathtemplate : cstring) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.SetCaptureFilePathTemplate(pathtemplate)
}

// returns the current capture path template, see SetCaptureFileTemplate above, as a UTF-8 string
GetCaptureFilePathTemplate :: proc "c" (rdoc_api: rawptr) -> string {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return {}
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return string(rdoc_api_internal.GetCaptureFilePathTemplate())
	} else {
		return {}
	}
}

// returns the number of captures that have been made
GetNumCaptures :: proc "c" (rdoc_api: rawptr) -> u32 {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.GetNumCaptures()
	} else {
		return 0
	}
}

// This function returns the details of a capture, by index. New captures are added
// to the end of the list.
//
// filename will be filled with the absolute path to the capture file, as a UTF-8 string
// pathlength will be written with the length in bytes of the filename string
// timestamp will be written with the time of the capture, in seconds since the Unix epoch
//
// Any of the parameters can be NULL and they'll be skipped.
//
// The function will return 1 if the capture index is valid, or 0 if the index is invalid
// If the index is invalid, the values will be unchanged
//
// Note: when captures are deleted in the UI they will remain in this list, so the
// capture path may not exist anymore.
GetCapture :: proc "c" (rdoc_api: rawptr, idx : u32, filename : cstring, pathlength : ^u32, timestamp : ^u64) -> u32 {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.GetCapture(idx, filename, pathlength, timestamp)
	} else {
		return 0
	}
}

// Sets the comments associated with a capture file. These comments are displayed in the
// UI program when opening.
//
// filePath should be a path to the capture file to add comments to. If set to NULL or ""
// the most recent capture file created made will be used instead.
// comments should be a NULL-terminated UTF-8 string to add as comments.
//
// Any existing comments will be overwritten.
@(disabled = !LOAD_RENDERDOC)
SetCaptureFileComments :: proc "c" (rdoc_api: rawptr, filePath : cstring, comments : cstring) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.SetCaptureFileComments(filePath, comments)
}

// returns 1 if the RenderDoc UI is connected to this application, 0 otherwise
IsTargetControlConnected :: proc "c" (rdoc_api: rawptr, ) -> bool {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return false
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.IsTargetControlConnected() == 1
	} else {
		return false
	}
}

// This function will launch the Replay UI associated with the RenderDoc library injected
// into the running application.
//
// if connectTargetControl is 1, the Replay UI will be launched with a command line parameter
// to connect to this application
// cmdline is the rest of the command line, as a UTF-8 string. E.g. a captures to open
// if cmdline is NULL, the command line will be empty.
//
// returns the PID of the replay UI if successful, 0 if not successful.
LaunchReplayUI :: proc "c" (rdoc_api: rawptr, connectTargetControl : u32, cmdline : cstring) -> u32 {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0
		}

		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.LaunchReplayUI(connectTargetControl, cmdline)
	} else {
		return 0
	}
}

// RenderDoc can return a higher version than requested if it's backwards compatible,
// this function returns the actual version returned. If a parameter is NULL, it will be
// ignored and the others will be filled out.
@(disabled = !LOAD_RENDERDOC)
GetAPIVersion :: proc "c" (rdoc_api: rawptr, major : ^c.int, minor : ^c.int, patch : ^c.int) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.GetAPIVersion(major, minor, patch)
}

// Requests that the replay UI show itself (if hidden or not the current top window). This can be
// used in conjunction with IsTargetControlConnected and LaunchReplayUI to intelligently handle
// showing the UI after making a capture.
//
// This will return 1 if the request was successfully passed on, though it's not guaranteed that
// the UI will be on top in all cases depending on OS rules. It will return 0 if there is no current
// target control connection to make such a request, or if there was another error
ShowReplayUI :: proc "c" (rdoc_api: rawptr) -> u32 {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.ShowReplayUI()
	} else {
		return 0
	}
}

@(disabled = !LOAD_RENDERDOC)
SetActiveWindow :: proc "c" (rdoc_api: rawptr, device : DevicePointer, wndHandle : WindowHandle) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.SetActiveWindow(device, wndHandle)
}

@(disabled = !LOAD_RENDERDOC)
TriggerCapture :: proc "c" (rdoc_api: rawptr) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.TriggerCapture()
}

@(disabled = !LOAD_RENDERDOC)
TriggerMultiFrameCapture :: proc "c" (rdoc_api: rawptr, numFrames : u32) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.TriggerMultiFrameCapture(numFrames)
}

@(disabled = !LOAD_RENDERDOC)
StartFrameCapture :: proc "c" (rdoc_api: rawptr, device : DevicePointer, wndHandle : WindowHandle) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.StartFrameCapture(device, wndHandle)
}

IsFrameCapturing :: proc "c" (rdoc_api: rawptr) -> bool {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return false
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.IsFrameCapturing() == 1
	} else {
		return false
	}
}

EndFrameCapture :: proc "c" (rdoc_api: rawptr, device : DevicePointer, wndHandle : WindowHandle) -> u32 {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.EndFrameCapture(device, wndHandle)
	} else {
		return 0
	}
}

DiscardFrameCapture :: proc "c" (rdoc_api: rawptr, device : DevicePointer, wndHandle : WindowHandle) -> u32 {
	when LOAD_RENDERDOC {
		if rdoc_api == nil {
			return 0
		}
		rdoc_api_internal := cast(^API_1_6_0) rdoc_api
		return rdoc_api_internal.DiscardFrameCapture(device, wndHandle)
	} else {
		return 0
	}
}

@(disabled = !LOAD_RENDERDOC)
SetCaptureTitle :: proc "c" (rdoc_api: rawptr, title : cstring) {
	if rdoc_api == nil {
		return
	}
	rdoc_api_internal := cast(^API_1_6_0) rdoc_api
	rdoc_api_internal.SetCaptureTitle(title)
}