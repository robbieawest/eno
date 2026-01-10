package ui

import im "../../../libs/dear-imgui"

import futils "../file_utils"
import dbg "../debug"
import "../utils"

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:slice"


// Returns picked_new as string pointing to the buffer
pick_file_from_explorer :: proc{ pick_file_from_explorer_raw, pick_file_from_explorer_buf }

pick_file_from_explorer_buf :: proc(buffer_label: string, label := "", file_extension := "*") -> (picked_new: string, ok: bool) {
    ctx := check_context() or_return
    return pick_file_from_explorer(get_buffer(ctx, buffer_label), ctx, label, file_extension)
}

pick_file_from_explorer_raw :: proc(buffer: []byte, ctx: ^UIContext, label := "", file_extension := "*") -> (picked_new: string, ok: bool) {
    if file_extension != "*" && !strings.starts_with(file_extension, ".") {
        dbg.log(.ERROR, "File extension must start with .")
        return
    }

    ctx := check_context() or_return

    label : cstring = len(label) == 0 ? "Open file explorer" : strings.clone_to_cstring(label, ctx.temp_allocator)
    if im.Button(label) {
        im.OpenPopup("#file_dialog")
    }

    @(static) extension_filter_options := []cstring{ "*", ".gltf", ".hdr", ".png", ".jpg" }
    @(static) selected_extension_filter := 0

    // I'm handling file_extension_c seperate in memory to file_extension and the filter options to create a standard between both options, but the procedure cold just be overloaded for each
    MAX_FILE_EXTENSION_LENGTH :: 5
    file_extension_c := cstring(raw_data(make_slice([]u8, MAX_FILE_EXTENSION_LENGTH + 1, ctx.temp_allocator)))
    if file_extension == "*" {
        mem.copy(rawptr(file_extension_c), rawptr(extension_filter_options[selected_extension_filter]), MAX_FILE_EXTENSION_LENGTH)
    }
    else {
        mem.copy(rawptr(file_extension_c), raw_data(file_extension), min(len(file_extension), MAX_FILE_EXTENSION_LENGTH))
    }

    if im.BeginPopupEx(im.GetID("#file_dialog"), { .NoSavedSettings, .NoTitleBar }) {
        defer im.EndPopup()

        cwd := ctx.working_dir
        im.Text("%s", fmt.aprintf("Directory : %s", cwd, allocator=ctx.temp_allocator))
        im.SameLine()
        if im.Button("<<") {
            decrement_ui_cwd(ctx) or_return
        }
        im.Spacing()
        im.Spacing()

        new_picked_file, new_picked_dir := display_directory_contents(cwd, string(file_extension_c), ctx.temp_allocator) or_return
        if len(new_picked_dir) != 0 {
            delete(cwd, ctx.allocator)
            ctx.working_dir = strings.clone(new_picked_dir, ctx.allocator)
        }
        else if new_picked_file != nil {
            utils.copy_and_zero(string(buffer), string(new_picked_file))
            im.CloseCurrentPopup()
            return string(buffer), true
        }

        im.Spacing()
        im.Spacing()

        im.Text(file_extension_c)
        if file_extension == "*" {
            // File extension dropdown

            if im.BeginCombo("File type filter", extension_filter_options[selected_extension_filter]) {
                defer im.EndCombo()

                for option, i in extension_filter_options {
                    is_selected := selected_extension_filter == i
                    if im.Selectable(extension_filter_options[i], is_selected) do selected_extension_filter = i

                    if is_selected do im.SetItemDefaultFocus()
                }
            }
        }

        im.Spacing()
        im.Spacing()
        if im.Button("Cancel") do im.CloseCurrentPopup()
    }

    ok = true
    return
}

@(private)
decrement_ui_cwd :: proc(ctx: ^UIContext) -> (ok: bool) {
    cwd := ctx.working_dir
    if len(cwd) == 0 {
        dbg.log(.ERROR, "CWD is invalid, length 0")
        return
    }
    last_is_seperator := os.is_path_separator(rune(cwd[len(cwd) - 1]))

    counted := 0
    i: int
    for i = len(cwd) - 1; i >= 0 && counted != 1 + int(last_is_seperator); i -= 1 {
        if os.is_path_separator(rune(cwd[i])) do counted += 1
    }
    if i == -1 do return true

    ctx.working_dir = cwd[:i+1]
    dbg.log(.INFO, "New ui working dir: %s", ctx.working_dir)
    return true
}

@(private)
display_directory_contents :: proc(current_working_dir: string, allowed_extension: string, temp_allocator: mem.Allocator) -> (picked: cstring, picked_cwd: string, ok: bool) {
    file_infos := futils.get_directory_contents(current_working_dir, allocator=temp_allocator) or_return

    directories := slice.filter(file_infos, proc(info: os.File_Info) -> bool { return info.is_dir}, temp_allocator)
    files := slice.filter(file_infos, proc(info: os.File_Info) -> bool { return !info.is_dir}, temp_allocator)

    for file_info, file_idx in slice.concatenate([][]os.File_Info{ directories, files }, allocator=temp_allocator) {  // Disgusting ;/
        file_info: os.File_Info = file_info

        if file_info.is_dir {
            if im.TreeNode(strings.clone_to_cstring(file_info.name, temp_allocator)) {
                defer im.TreePop()
                new_picked_file, new_picked_cwd := display_directory_contents(file_info.fullpath, allowed_extension, temp_allocator) or_return
                if len(new_picked_cwd) != 0 do return nil, new_picked_cwd, true
                else if new_picked_file != nil do return new_picked_file, "", true
            }
            else {
                im.SameLine(spacing = 15)
                enter_button_label := fmt.caprintf("<##dir_%s", file_info.fullpath, allocator=temp_allocator)
                if im.Button(enter_button_label) do return nil, file_info.fullpath, true
            }
        }
        else {
            _, extension := futils.split_extension_from_path(file_info.fullpath, temp_allocator) or_return
            if len(extension) != 0 && (strings.compare(allowed_extension, "*") == 0 || strings.compare(extension, allowed_extension[1:]) == 0) {
                name_button_label := fmt.caprintf("%s##button_%s", file_info.name, file_info.fullpath)
                if im.Button(name_button_label) {
                    dbg.log(.INFO, "Picked file: %s", file_info.fullpath)
                    return strings.clone_to_cstring(file_info.fullpath, temp_allocator), "", true
                }
            }
        }

    }

    ok = true
    return
}
