package ui

import im "../../../libs/dear-imgui"

import futils "../file_utils"
import dbg "../debug"
import "../utils"

import "core:mem"
import "core:os"
import "core:strings"
import "core:slice"

pick_file_from_explorer :: proc(buffer: []byte, label := "", file_extension := "*") -> (ok: bool) {
    ctx := check_context() or_return
    im.SetNextWindowSize(im.Vec2{ 400, 400 }, .Always)  // Todo define elsewhere, best based on window resolution

    label : cstring = len(label) == 0 ? "Open file explorer" : strings.clone_to_cstring(label, ctx.temp_allocator)
    if im.Button(label) {
        im.OpenPopup("#file_dialog")
    }

    MAX_FILE_EXTENSION_LENGTH :: 5
    file_extension_c := cstring(raw_data(make_slice([]u8, MAX_FILE_EXTENSION_LENGTH + 1, ctx.temp_allocator)))

    mem.copy(rawptr(file_extension_c), rawptr(strings.clone_to_cstring(file_extension, ctx.temp_allocator)), min(len(file_extension) + 1, MAX_FILE_EXTENSION_LENGTH))
    if im.BeginPopupEx(im.GetID("#file_dialog"), { .Popup }) {
        defer im.EndPopup()

        new_picked_file := display_directory_contents(os.get_current_directory(allocator=ctx.temp_allocator), string(file_extension), ctx.temp_allocator) or_return
        if new_picked_file != nil {
            utils.copy_and_zero(string(buffer), string(new_picked_file))
            dbg.log(.INFO, "Setting new %s picked %s", new_picked_file, buffer)
            im.CloseCurrentPopup()
        }

        if im.Button("Cancel") do im.CloseCurrentPopup()

        if len(file_extension) == 0 {
            if im.BeginCombo("File type", file_extension_c) {
                defer im.EndCombo()

                // Todo
            }
        }

        im.Text(file_extension_c)
    }

    return true
}

display_directory_contents :: proc(current_working_dir: string, allowed_extension: string, temp_allocator: mem.Allocator) -> (picked_file: cstring, ok: bool) {
    file_infos := futils.get_directory_contents(current_working_dir, allocator=temp_allocator) or_return

    directories := slice.filter(file_infos, proc(info: os.File_Info) -> bool { return info.is_dir}, temp_allocator)
    files := slice.filter(file_infos, proc(info: os.File_Info) -> bool { return !info.is_dir}, temp_allocator)

    for file_info in slice.concatenate([][]os.File_Info{ directories, files }, allocator=temp_allocator) {  // Disgusting ;/
        file_info: os.File_Info = file_info

        if file_info.is_dir {
            if im.TreeNode(strings.clone_to_cstring(file_info.name, temp_allocator)) {
                defer im.TreePop()
                new_picked_file := display_directory_contents(file_info.fullpath, allowed_extension, temp_allocator) or_return
                if new_picked_file != nil do return new_picked_file, true
            }
        }
        else {
            base_path, extension := futils.split_extension_from_path(file_info.fullpath, temp_allocator) or_return
            if len(extension) != 0 && (strings.compare(allowed_extension, "*") == 0 || strings.compare(extension, allowed_extension) == 0) {
                name_cstr := strings.clone_to_cstring(file_info.name, temp_allocator)
                if im.Button(name_cstr) {
                    picked_file = strings.clone_to_cstring(file_info.fullpath, temp_allocator)
                    dbg.log(.INFO, "Picked file: %s", picked_file)
                }
            }
        }

    }

    ok = true
    return
}
