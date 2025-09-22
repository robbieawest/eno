package renderdoc

// @NOTE: this file was generated 
// from https://github.com/baldurk/renderdoc/blob/v1.x/renderdoc/api/app/renderdoc_app.h 
// using bindgen https://github.com/Breush/odin-binding-generator
// most comments have been copied over for convinience, but some may be incorrect, refer the original header file for more accurate info
// also check the docs: https://renderdoc.org/docs/in_application_api.html

import "core:c"

// required only for DEVICEPOINTER_FROM_VKINSTANCE
import vk "vendor:vulkan"

//////////////////////////////////////////////////////////////////////////////////////////////////
// Constants not used directly in below API

// This is a GUID/magic value used for when applications pass a path where shader debug
// information can be found to match up with a stripped shader.
// the define can be used like so: const GUID ShaderDebugMagicValue =
// ShaderDebugMagicValue_value
ShaderDebugMagicValue : u64 : 0x48656670eab25520

// Sets an option that controls how RenderDoc behaves on capture.
//
// Returns 1 if the option and value are valid
// Returns 0 if either is invalid and the option is unchanged
SetCaptureOptionU32Proc :: #type proc "c" (opt : CaptureOption, val : u32) -> c.int
SetCaptureOptionF32Proc :: #type proc "c" (opt : CaptureOption, val : f32) -> c.int

// Gets the current value of an option as a uint32_t
//
// If the option is invalid, 0xffffffff is returned
GetCaptureOptionU32Proc :: #type proc "c" (opt : CaptureOption) -> u32

// Gets the current value of an option as a float
//
// If the option is invalid, -FLT_MAX is returned
GetCaptureOptionF32Proc :: #type proc "c" (opt : CaptureOption) -> f32

// Sets which key or keys can be used to toggle focus between multiple windows
//
// If keys is NULL or num is 0, toggle keys will be disabled
SetFocusToggleKeysProc :: #type proc "c" (keys : [^]InputButton, num : c.int)

// Sets which key or keys can be used to capture the next frame
//
// If keys is NULL or num is 0, captures keys will be disabled
SetCaptureKeysProc :: #type proc "c" (keys : [^]InputButton, num : c.int)

// returns the overlay bits that have been set
GetOverlayBitsProc :: #type proc "c" () -> u32

// sets the overlay bits with an and & or mask
MaskOverlayBitsProc :: #type proc "c" (And : u32, Or : u32)

// this function will attempt to remove RenderDoc's hooks in the application.
//
// Note: that this can only work correctly if done immediately after
// the module is loaded, before any API work happens. RenderDoc will remove its
// injected hooks and shut down. Behaviour is undefined if this is called
// after any API functions have been called, and there is still no guarantee of
// success.
RemoveHooksProc :: #type proc "c" ()

// This function will unload RenderDoc's crash handler.
//
// If you use your own crash handler and don't want RenderDoc's handler to
// intercede, you can call this function to unload it and any unhandled
// exceptions will pass to the next handler.
UnloadCrashHandlerProc :: #type proc "c" ()

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
SetCaptureFilePathTemplateProc :: #type proc "c" (pathtemplate : cstring)

// returns the current capture path template, see SetCaptureFileTemplate above, as a UTF-8 string
GetCaptureFilePathTemplateProc :: #type proc "c" () -> cstring

// returns the number of captures that have been made
GetNumCapturesProc :: #type proc "c" () -> u32

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
GetCaptureProc :: #type proc "c" (idx : u32, filename : cstring, pathlength : ^u32, timestamp : ^u64) -> u32

// Sets the comments associated with a capture file. These comments are displayed in the
// UI program when opening.
//
// filePath should be a path to the capture file to add comments to. If set to NULL or ""
// the most recent capture file created made will be used instead.
// comments should be a NULL-terminated UTF-8 string to add as comments.
//
// Any existing comments will be overwritten.
SetCaptureFileCommentsProc :: #type proc "c" (filePath : cstring, comments : cstring)

// returns 1 if the RenderDoc UI is connected to this application, 0 otherwise
IsTargetControlConnectedProc :: #type proc "c" () -> u32

// This function will launch the Replay UI associated with the RenderDoc library injected
// into the running application.
//
// if connectTargetControl is 1, the Replay UI will be launched with a command line parameter
// to connect to this application
// cmdline is the rest of the command line, as a UTF-8 string. E.g. a captures to open
// if cmdline is NULL, the command line will be empty.
//
// returns the PID of the replay UI if successful, 0 if not successful.
LaunchReplayUIProc :: #type proc "c" (connectTargetControl : u32, cmdline : cstring) -> u32

// RenderDoc can return a higher version than requested if it's backwards compatible,
// this function returns the actual version returned. If a parameter is NULL, it will be
// ignored and the others will be filled out.
GetAPIVersionProc :: #type proc "c" (major : ^c.int, minor : ^c.int, patch : ^c.int)

// Requests that the replay UI show itself (if hidden or not the current top window). This can be
// used in conjunction with IsTargetControlConnected and LaunchReplayUI to intelligently handle
// showing the UI after making a capture.
//
// This will return 1 if the request was successfully passed on, though it's not guaranteed that
// the UI will be on top in all cases depending on OS rules. It will return 0 if there is no current
// target control connection to make such a request, or if there was another error
ShowReplayUIProc :: #type proc "c" () -> u32

//////////////////////////////////////////////////////////////////////////
// Capturing functions
//

// A device pointer is a pointer to the API's root handle.
//
// This would be an ID3D11Device, HGLRC/GLXContext, ID3D12Device, etc
DevicePointer :: rawptr

// A window handle is the OS's native window handle
//
// This would be an HWND, GLXDrawable, etc
WindowHandle :: rawptr

// A helper macro for Vulkan, where the device handle cannot be used directly.
//
// Passing the VkInstance to this macro will return the DevicePointer to use.
//
// Specifically, the value needed is the dispatch table pointer, which sits as the first
// pointer-sized object in the memory pointed to by the VkInstance. Thus we cast to a void** and
// indirect once.
DEVICEPOINTER_FROM_VKINSTANCE :: proc "c" (inst: vk.Instance) -> DevicePointer {
	return (cast(^rawptr)inst)^
}

SetActiveWindowProc :: #type proc "c" (device : DevicePointer, wndHandle : WindowHandle)
TriggerCaptureProc :: #type proc "c" ()
TriggerMultiFrameCaptureProc :: #type proc "c" (numFrames : u32)
StartFrameCaptureProc :: #type proc "c" (device : DevicePointer, wndHandle : WindowHandle)
IsFrameCapturingProc :: #type proc "c" () -> u32
EndFrameCaptureProc :: #type proc "c" (device : DevicePointer, wndHandle : WindowHandle) -> u32
DiscardFrameCaptureProc :: #type proc "c" (device : DevicePointer, wndHandle : WindowHandle) -> u32
SetCaptureTitleProc :: #type proc "c" (title : cstring)

//////////////////////////////////////////////////////////////////////////////////////////////////
// RenderDoc API entry point
//
// This entry point can be obtained via GetProcAddress/dlsym if RenderDoc is available.
//
// The name is the same as the typedef - "GetAPIProc"
//
// This function is not thread safe, and should not be called on multiple threads at once.
// Ideally, call this once as early as possible in your application's startup, before doing
// any API work, since some configuration functionality etc has to be done also before
// initialising any APIs.
//
// Parameters:
//   version is a single value from the Version above.
//
//   outAPIPointers will be filled out with a pointer to the corresponding struct of function
//   pointers.
//
// Returns:
//   1 - if the outAPIPointers has been filled with a pointer to the API struct requested
//   0 - if the requested version is not supported or the arguments are invalid.
//
GetAPIProc :: #type proc "c" (version : Version, outAPIPointers : ^rawptr) -> c.int

//////////////////////////////////////////////////////////////////////////////////////////////////
// RenderDoc capture options
//

CaptureOption :: enum i32 {
	// Allow the application to enable vsync
	//
	// Default - enabled
	//
	// 1 - The application can enable or disable vsync at will
	// 0 - vsync is force disabled
	AllowVSync = 0,

	// Allow the application to enable fullscreen
	//
	// Default - enabled
	//
	// 1 - The application can enable or disable fullscreen at will
	// 0 - fullscreen is force disabled
	AllowFullscreen = 1,

	// Record API debugging events and messages
	//
	// Default - disabled
	//
	// 1 - Enable built-in API debugging features and records the results into
	//     the capture, which is matched up with events on replay
	// 0 - no API debugging is forcibly enabled
	APIValidation = 2,

	// Capture CPU callstacks for API events
	//
	// Default - disabled
	//
	// 1 - Enables capturing of callstacks
	// 0 - no callstacks are captured
	CaptureCallstacks = 3,

	// When capturing CPU callstacks, only capture them from actions.
	// This option does nothing without the above option being enabled
	//
	// Default - disabled
	//
	// 1 - Only captures callstacks for actions.
	//     Ignored if CaptureCallstacks is disabled
	// 0 - Callstacks, if enabled, are captured for every event.
	CaptureCallstacksOnlyDraws = 4,
	CaptureCallstacksOnlyActions = 4,

	// Specify a delay in seconds to wait for a debugger to attach, after
	// creating or injecting into a process, before continuing to allow it to run.
	//
	// 0 indicates no delay, and the process will run immediately after injection
	//
	// Default - 0 seconds
	//
	DelayForDebugger = 5,

	// Verify buffer access. This includes checking the memory returned by a Map() call to
	// detect any out-of-bounds modification, as well as initialising buffers with undefined contents
	// to a marker value to catch use of uninitialised memory.
	//
	// NOTE: This option is only valid for OpenGL and D3D11. Explicit APIs such as D3D12 and Vulkan do
	// not do the same kind of interception & checking and undefined contents are really undefined.
	//
	// Default - disabled
	//
	// 1 - Verify buffer access
	// 0 - No verification is performed, and overwriting bounds may cause crashes or corruption in
	//     RenderDoc.
	VerifyBufferAccess = 6,

	// The old name for VerifyBufferAccess was VerifyMapWrites.
	// This option now controls the filling of uninitialised buffers with 0xdddddddd which was
	// previously always enabled
	VerifyMapWrites = VerifyBufferAccess,

	// Hooks any system API calls that create child processes, and injects
	// RenderDoc into them recursively with the same options.
	//
	// Default - disabled
	//
	// 1 - Hooks into spawned child processes
	// 0 - Child processes are not hooked by RenderDoc
	HookIntoChildren = 7,

	// By default RenderDoc only includes resources in the final capture necessary
	// for that frame, this allows you to override that behaviour.
	//
	// Default - disabled
	//
	// 1 - all live resources at the time of capture are included in the capture
	//     and available for inspection
	// 0 - only the resources referenced by the captured frame are included
	RefAllResources = 8,

	// In APIs that allow for the recording of command lists to be replayed later,
	// RenderDoc may choose to not capture command lists before a frame capture is
	// triggered, to reduce overheads. This means any command lists recorded once
	// and replayed many times will not be available and may cause a failure to
	// capture.
	//
	// NOTE: This is only true for APIs where multithreading is difficult or
	// discouraged. Newer APIs like Vulkan and D3D12 will ignore this option
	// and always capture all command lists since the API is heavily oriented
	// around it and the overheads have been reduced by API design.
	//
	// 1 - All command lists are captured from the start of the application
	// 0 - Command lists are only captured if their recording begins during
	//     the period when a frame capture is in progress.
	CaptureAllCmdLists = 10,

	// Mute API debugging output when the API validation mode option is enabled
	//
	// Default - enabled
	//
	// 1 - Mute any API debug messages from being displayed or passed through
	// 0 - API debugging is displayed as normal
	DebugOutputMute = 11,

	// Option to allow vendor extensions to be used even when they may be
	// incompatible with RenderDoc and cause corrupted replays or crashes.
	//
	// Default - inactive
	//
	// No values are documented, this option should only be used when absolutely
	// necessary as directed by a RenderDoc developer.
	AllowUnsupportedVendorExtensions = 12,

	// Define a soft memory limit which some APIs may aim to keep overhead under where
	// possible. Anything above this limit will where possible be saved directly to disk during
	// capture.
	// This will cause increased disk space use (which may cause a capture to fail if disk space is
	// exhausted) as well as slower capture times.
	//
	// Not all memory allocations may be deferred like this so it is not a guarantee of a memory
	// limit.
	//
	// Units are in MBs, suggested values would range from 200MB to 1000MB.
	//
	// Default - 0 Megabytes
	SoftMemoryLimit = 13,
}

InputButton :: enum i32 {
	// '0' - '9' matches ASCII values
	Key_0 = 0x30,
	Key_1 = 0x31,
	Key_2 = 0x32,
	Key_3 = 0x33,
	Key_4 = 0x34,
	Key_5 = 0x35,
	Key_6 = 0x36,
	Key_7 = 0x37,
	Key_8 = 0x38,
	Key_9 = 0x39,

	// 'A' - 'Z' matches ASCII values
	Key_A = 0x41,
	Key_B = 0x42,
	Key_C = 0x43,
	Key_D = 0x44,
	Key_E = 0x45,
	Key_F = 0x46,
	Key_G = 0x47,
	Key_H = 0x48,
	Key_I = 0x49,
	Key_J = 0x4A,
	Key_K = 0x4B,
	Key_L = 0x4C,
	Key_M = 0x4D,
	Key_N = 0x4E,
	Key_O = 0x4F,
	Key_P = 0x50,
	Key_Q = 0x51,
	Key_R = 0x52,
	Key_S = 0x53,
	Key_T = 0x54,
	Key_U = 0x55,
	Key_V = 0x56,
	Key_W = 0x57,
	Key_X = 0x58,
	Key_Y = 0x59,
	Key_Z = 0x5A,

	// leave the rest of the ASCII range free
	// in case we want to use it later
	Key_NonPrintable = 0x100,

	Key_Divide,
	Key_Multiply,
	Key_Subtract,
	Key_Plus,

	Key_F1,
	Key_F2,
	Key_F3,
	Key_F4,
	Key_F5,
	Key_F6,
	Key_F7,
	Key_F8,
	Key_F9,
	Key_F10,
	Key_F11,
	Key_F12,

	Key_Home,
	Key_End,
	Key_Insert,
	Key_Delete,
	Key_PageUp,
	Key_PageDn,

	Key_Backspace,
	Key_Tab,
	Key_PrtScrn,
	Key_Pause,

	Key_Max,
}

OverlayBits :: enum u32 {
	// This single bit controls whether the overlay is enabled or disabled globally
	Enabled = 0x1,

	// Show the average framerate over several seconds as well as min/max
	FrameRate = 0x2,

	// Show the current frame number
	FrameNumber = 0x4,

	// Show a list of recent captures, and how many captures have been made
	CaptureList = 0x8,

		// Default values for the overlay mask
	Default = (Enabled | FrameRate | FrameNumber | CaptureList),

	// Enable all bits
	All = 0xffffffff,

	// Disable all bits
	None = 0,
}

//////////////////////////////////////////////////////////////////////////////////////////////////
// RenderDoc API versions
//

// RenderDoc uses semantic versioning (http://semver.org/).
//
// MAJOR version is incremented when incompatible API changes happen.
// MINOR version is incremented when functionality is added in a backwards-compatible manner.
// PATCH version is incremented when backwards-compatible bug fixes happen.
//
// Note that this means the API returned can be higher than the one you might have requested.
// e.g. if you are running against a newer RenderDoc that supports 1.0.1, it will be returned
// instead of 1.0.0. You can check this with the GetAPIVersion entry point
Version :: enum i32 {
	API_Version_1_0_0 = 10000,    // API_1_0_0 = 1 00 00
	API_Version_1_0_1 = 10001,    // API_1_0_1 = 1 00 01
	API_Version_1_0_2 = 10002,    // API_1_0_2 = 1 00 02
	API_Version_1_1_0 = 10100,    // API_1_1_0 = 1 01 00
	API_Version_1_1_1 = 10101,    // API_1_1_1 = 1 01 01
	API_Version_1_1_2 = 10102,    // API_1_1_2 = 1 01 02
	API_Version_1_2_0 = 10200,    // API_1_2_0 = 1 02 00
	API_Version_1_3_0 = 10300,    // API_1_3_0 = 1 03 00
	API_Version_1_4_0 = 10400,    // API_1_4_0 = 1 04 00
	API_Version_1_4_1 = 10401,    // API_1_4_1 = 1 04 01
	API_Version_1_4_2 = 10402,    // API_1_4_2 = 1 04 02
	API_Version_1_5_0 = 10500,    // API_1_5_0 = 1 05 00
	API_Version_1_6_0 = 10600,    // API_1_6_0 = 1 06 00
}

API_1_6_0 :: struct {
	GetAPIVersion : GetAPIVersionProc,
	SetCaptureOptionU32 : SetCaptureOptionU32Proc,
	SetCaptureOptionF32 : SetCaptureOptionF32Proc,
	GetCaptureOptionU32 : GetCaptureOptionU32Proc,
	GetCaptureOptionF32 : GetCaptureOptionF32Proc,
	SetFocusToggleKeys : SetFocusToggleKeysProc,
	SetCaptureKeys : SetCaptureKeysProc,
	GetOverlayBits : GetOverlayBitsProc,
	MaskOverlayBits : MaskOverlayBitsProc,
	RemoveHooks : RemoveHooksProc,
	UnloadCrashHandler : UnloadCrashHandlerProc,
	SetCaptureFilePathTemplate : SetCaptureFilePathTemplateProc,
	GetCaptureFilePathTemplate : GetCaptureFilePathTemplateProc,
	GetNumCaptures : GetNumCapturesProc,
	GetCapture : GetCaptureProc,
	TriggerCapture : TriggerCaptureProc,
	IsTargetControlConnected : IsTargetControlConnectedProc,
	LaunchReplayUI : LaunchReplayUIProc,
	SetActiveWindow : SetActiveWindowProc,
	StartFrameCapture : StartFrameCaptureProc,
	IsFrameCapturing : IsFrameCapturingProc,
	EndFrameCapture : EndFrameCaptureProc,
	TriggerMultiFrameCapture : TriggerMultiFrameCaptureProc,
	SetCaptureFileComments : SetCaptureFileCommentsProc,
	DiscardFrameCapture : DiscardFrameCaptureProc,
	ShowReplayUI : ShowReplayUIProc,
	SetCaptureTitle : SetCaptureTitleProc,
}

API_1_0_0 :: API_1_6_0
API_1_0_1 :: API_1_6_0
API_1_0_2 :: API_1_6_0
API_1_1_0 :: API_1_6_0
API_1_1_1 :: API_1_6_0
API_1_1_2 :: API_1_6_0
API_1_2_0 :: API_1_6_0
API_1_3_0 :: API_1_6_0
API_1_4_0 :: API_1_6_0
API_1_4_1 :: API_1_6_0
API_1_4_2 :: API_1_6_0
API_1_5_0 :: API_1_6_0