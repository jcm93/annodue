const std = @import("std");

const mp = @import("patch_multiplayer.zig");
const gen = @import("patch_general.zig");
const practice = @import("patch_practice.zig");
const savestate = @import("patch_savestate.zig");

const msg = @import("util/message.zig");
const mem = @import("util/memory.zig");
const input = @import("util/input.zig");
const r = @import("util/racer.zig");
const rc = @import("util/racer_const.zig");
const rf = @import("util/racer_fn.zig");
const SettingsGroup = @import("util/settings.zig").SettingsGroup;
const SettingsManager = @import("util/settings.zig").SettingsManager;

const ini = @import("import/import.zig").ini;
const win32 = @import("import/import.zig").win32;
const win32kb = win32.ui.input.keyboard_and_mouse;
const win32wm = win32.ui.windows_and_messaging;
const KS_DOWN: i16 = -1;
const KS_PRESSED: i16 = 1; // since last call

const VirtualAlloc = std.os.windows.VirtualAlloc;
const VirtualFree = std.os.windows.VirtualFree;
const MEM_COMMIT = std.os.windows.MEM_COMMIT;
const MEM_RESERVE = std.os.windows.MEM_RESERVE;
const MEM_RELEASE = std.os.windows.MEM_RELEASE;
const PAGE_EXECUTE_READWRITE = std.os.windows.PAGE_EXECUTE_READWRITE;
const WINAPI = std.os.windows.WINAPI;
const WPARAM = std.os.windows.WPARAM;
const LPARAM = std.os.windows.LPARAM;
const LRESULT = std.os.windows.LRESULT;
const HINSTANCE = std.os.windows.HINSTANCE;
const HWND = std.os.windows.HWND;

// STATE

const patch_size: u32 = 4 * 1024 * 1024; // 4MB

const ver_major: u32 = 0;
const ver_minor: u32 = 0;
const ver_patch: u32 = 1;

const s = struct { // FIXME: yucky
    var manager: SettingsManager = undefined;
    var gen: SettingsGroup = undefined;
    var prac: SettingsGroup = undefined;
    var mp: SettingsGroup = undefined;
};

const global = struct {
    var practice_mode: bool = false;
    var hwnd: ?HWND = null;
    var hinstance: ?HINSTANCE = null;
};

// ???

fn DrawMenuPracticeModeLabel() void {
    if (global.practice_mode) {
        rf.swrText_CreateEntry1(640 - 20, 16, 255, 255, 255, 255, "~F0~3~s~rPractice Mode");
    }
}

// GAME LOOP

fn GameLoop_Before() void {
    const state = struct {
        var initialized: bool = false;
    };

    input.update_kb();

    if (!state.initialized) {
        const def_laps: u32 = s.gen.get("default_laps", u32);
        if (def_laps >= 1 and def_laps <= 5) {
            const laps: usize = mem.deref(&.{ 0x4BFDB8, 0x8F });
            _ = mem.write(laps, u8, @as(u8, @truncate(def_laps)));
        }
        const def_racers: u32 = s.gen.get("default_racers", u32);
        if (def_racers >= 1 and def_racers <= 12) {
            const addr_racers: usize = 0x50C558;
            _ = mem.write(addr_racers, u8, @as(u8, @truncate(def_racers)));
        }

        state.initialized = true;
    }

    const in_race: bool = mem.read(rc.ADDR_IN_RACE, u8) > 0;

    if (input.get_kb_pressed(.P) and
        (!(in_race and global.practice_mode)))
    {
        global.practice_mode = !global.practice_mode;
    }

    if (in_race and input.get_kb_down(.@"2") and input.get_kb_pressed(.ESCAPE)) {
        const jdge: usize = mem.deref_read(&.{ rc.ADDR_ENTITY_MANAGER_JUMP_TABLE, @intFromEnum(rc.ENTITY.Jdge) * 4, 0x10 }, usize);
        rf.TriggerLoad_InRace(jdge, rc.MAGIC_RSTR);
    }

    if (in_race) {
        const pause: u8 = mem.read(rc.ADDR_PAUSE_STATE, u8);
        if (input.get_kb_pressed(.I))
            _ = mem.write(rc.ADDR_PAUSE_STATE, u8, (pause + 1) % 2);
    }

    practice.GameLoop_Before();

    if (s.gen.get("rainbow_timer_enable", bool)) {
        gen.PatchHudTimerColRotate();
    }
}

fn GameLoop_After() void {
    savestate.GameLoop_After(global.practice_mode);
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0GameLoop_After");
}

fn HookGameLoop(memory: usize) usize {
    return mem.intercept_call(memory, 0x49CE2A, &GameLoop_Before, &GameLoop_After);
}

// GAME END; executable closing

fn GameEnd() void {
    defer s.manager.deinit();
    defer s.gen.deinit();
    defer s.mp.deinit();
}

fn HookGameEnd(memory: usize) usize {
    const exit1_off: usize = 0x49CE31;
    const exit2_off: usize = 0x49CE3D;
    const exit1_len: usize = exit2_off - exit1_off - 1; // excluding retn
    const exit2_len: usize = 0x49CE48 - exit2_off - 1; // excluding retn
    var offset: usize = memory;

    offset = mem.detour(offset, exit1_off, exit1_len, null, &GameEnd);
    offset = mem.detour(offset, exit2_off, exit2_len, null, &GameEnd);

    return offset;
}

// MENU DRAW CALLS in 'Hang' callback0x14

fn MenuTitleScreen_Before() void {
    var buf_name: [127:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf_name, "~F0~sAnnodue {d}.{d}.{d}", .{
        ver_major,
        ver_minor,
        ver_patch,
    }) catch return;
    rf.swrText_CreateEntry1(36, 480 - 24, 255, 255, 255, 255, &buf_name);
    DrawMenuPracticeModeLabel();
}

fn MenuVehicleSelect_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuVehicleSelect_Before");
}

fn MenuStartRace_Before() void {
    DrawMenuPracticeModeLabel();
    //savestate.MenuStartRace_Before();
}

fn MenuJunkyard_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuJunkyard_Before");
}

fn MenuRaceResults_Before() void {
    DrawMenuPracticeModeLabel();
}

fn MenuWattosShop_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuWattosShop_Before");
}

fn MenuHangar_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuHangar_Before");
}

fn MenuTrackSelect_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuTrackSelect_Before");
}

fn MenuTrack_Before() void {
    DrawMenuPracticeModeLabel();
}

fn MenuCantinaEntry_Before() void {
    //swrText_CreateEntry1(16, 16, 255, 255, 255, 255, "~F0MenuCantinaEntry_Before");
}

fn HookMenuDrawing(memory: usize) usize {
    var off: usize = memory;

    // before 0x435240
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 1, &MenuTitleScreen_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 3, &MenuStartRace_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 4, &MenuJunkyard_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 5, &MenuRaceResults_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 7, &MenuWattosShop_Before);
    // before 0x______; inspect vehicle, view upgrades, etc.
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 8, &MenuHangar_Before);
    // before 0x435700
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 9, &MenuVehicleSelect_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 12, &MenuTrackSelect_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 13, &MenuTrack_Before);
    // before 0x______
    off = mem.intercept_jump_table(off, rc.ADDR_DRAW_MENU_JUMP_TABLE, 18, &MenuCantinaEntry_Before);

    return off;
}

// TEXT RENDER QUEUE FLUSHING

fn TextRender_Before() void {
    if (s.prac.get("practice_tool_enable", bool) and s.prac.get("overlay_enable", bool)) {
        practice.TextRender_Before(global.practice_mode);
    }
}

fn HookTextRender(memory: usize) usize {
    return mem.intercept_call(memory, 0x483F8B, null, &TextRender_Before);
}

// DO THE THING!!!

export fn Patch() void {
    const mem_alloc = MEM_COMMIT | MEM_RESERVE;
    const mem_protect = PAGE_EXECUTE_READWRITE;
    const memory = VirtualAlloc(null, patch_size, mem_alloc, mem_protect) catch unreachable;
    var off: usize = @intFromPtr(memory);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    // settings

    // FIXME: deinits happen in GameEnd, see HookGameEnd.
    // probably not necessary to deinit at all tho.
    // one other strategy might be to set globals for stuff
    // we need to keep, and go back to deinit-ing. then we also
    // wouldn't have to do hash lookups constantly too.

    s.manager = SettingsManager.init(alloc);
    //defer s.deinit();

    s.gen = SettingsGroup.init(alloc, "general");
    //defer s.gen.deinit();
    s.gen.add("death_speed_mod_enable", bool, false);
    s.gen.add("death_speed_min", f32, 325);
    s.gen.add("death_speed_drop", f32, 140);
    s.gen.add("rainbow_timer_enable", bool, false);
    s.gen.add("ms_timer_enable", bool, false);
    s.gen.add("default_laps", u32, 3);
    s.gen.add("default_racers", u32, 12);
    s.manager.add(&s.gen);

    s.prac = SettingsGroup.init(alloc, "practice");
    //defer s.prac.deinit();
    s.prac.add("practice_tool_enable", bool, false);
    s.prac.add("overlay_enable", bool, false);
    s.manager.add(&s.prac);

    s.mp = SettingsGroup.init(alloc, "multiplayer");
    //defer s.mp.deinit();
    s.mp.add("multiplayer_mod_enable", bool, false); // working?
    s.mp.add("patch_netplay", bool, false); // working? ups ok, coll ?
    s.mp.add("netplay_guid", bool, false); // working?
    s.mp.add("netplay_r100", bool, false); // working
    s.mp.add("patch_audio", bool, false); // FIXME: crashes
    s.mp.add("patch_fonts", bool, false); // working
    s.mp.add("fonts_dump", bool, false); // working?
    s.mp.add("patch_tga_loader", bool, false); // FIXME: need tga files to verify with
    s.mp.add("patch_trigger_display", bool, false); // working
    s.manager.add(&s.mp);

    s.manager.read_ini(alloc, "annodue/settings.ini") catch unreachable;

    // input-based launch toggles

    const kb_shift: i16 = win32kb.GetAsyncKeyState(@intFromEnum(win32kb.VK_SHIFT));
    const kb_shift_dn: bool = (kb_shift & KS_DOWN) != 0;
    global.practice_mode = kb_shift_dn;

    // hooking

    global.hwnd = mem.read(rc.ADDR_HWND, HWND);
    global.hinstance = mem.read(rc.ADDR_HINSTANCE, HINSTANCE);

    off = HookGameLoop(off);
    off = HookGameEnd(off);
    off = HookTextRender(off);
    off = HookMenuDrawing(off);

    // init: general stuff

    if (s.gen.get("death_speed_mod_enable", bool)) {
        const dsm = s.gen.get("death_speed_min", f32);
        const dsd = s.gen.get("death_speed_drop", f32);
        gen.PatchDeathSpeed(dsm, dsd);
    }
    if (s.gen.get("ms_timer_enable", bool)) {
        gen.PatchHudTimerMs();
    }

    // init: swe1r-patcher (multiplayer mod) stuff

    if (s.mp.get("multiplayer_mod_enable", bool)) {
        if (s.mp.get("fonts_dump", bool)) {
            // This is a debug feature to dump the original font textures
            _ = mp.DumpTextureTable(alloc, 0x4BF91C, 3, 0, 64, 128, "font0");
            _ = mp.DumpTextureTable(alloc, 0x4BF7E4, 3, 0, 64, 128, "font1");
            _ = mp.DumpTextureTable(alloc, 0x4BF84C, 3, 0, 64, 128, "font2");
            _ = mp.DumpTextureTable(alloc, 0x4BF8B4, 3, 0, 64, 128, "font3");
            _ = mp.DumpTextureTable(alloc, 0x4BF984, 3, 0, 64, 128, "font4");
        }
        if (s.mp.get("patch_fonts", bool)) {
            off = mp.PatchTextureTable(alloc, off, 0x4BF91C, 0x42D745, 0x42D753, 512, 1024, "font0");
            off = mp.PatchTextureTable(alloc, off, 0x4BF7E4, 0x42D786, 0x42D794, 512, 1024, "font1");
            off = mp.PatchTextureTable(alloc, off, 0x4BF84C, 0x42D7C7, 0x42D7D5, 512, 1024, "font2");
            off = mp.PatchTextureTable(alloc, off, 0x4BF8B4, 0x42D808, 0x42D816, 512, 1024, "font3");
            off = mp.PatchTextureTable(alloc, off, 0x4BF984, 0x42D849, 0x42D857, 512, 1024, "font4");
        }
        if (s.mp.get("patch_netplay", bool)) {
            const r100 = s.mp.get("netplay_r100", bool);
            const guid = s.mp.get("netplay_guid", bool);
            const traction: u8 = if (r100) 3 else 5;
            var upgrade_lv: [7]u8 = .{ traction, 5, 5, 5, 5, 5, 5 };
            var upgrade_hp: [7]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
            const upgrade_lv_ptr: *[7]u8 = @ptrCast(&upgrade_lv);
            const upgrade_hp_ptr: *[7]u8 = @ptrCast(&upgrade_hp);
            off = mp.PatchNetworkUpgrades(off, upgrade_lv_ptr, upgrade_hp_ptr, guid);
            off = mp.PatchNetworkCollisions(off, guid);
        }
        if (s.mp.get("patch_audio", bool)) {
            const sample_rate: u32 = 22050 * 2;
            const bits_per_sample: u8 = 16;
            const stereo: bool = true;
            mp.PatchAudioStreamQuality(sample_rate, bits_per_sample, stereo);
        }
        if (s.mp.get("patch_tga_loader", bool)) {
            off = mp.PatchSpriteLoaderToLoadTga(off);
        }
        if (s.mp.get("patch_trigger_display", bool)) {
            off = mp.PatchTriggerDisplay(off);
        }
    }

    // debug

    if (false) {
        msg.Message("Annodue {d}.{d}.{d}", .{
            ver_major,
            ver_minor,
            ver_patch,
        }, "Patching SWE1R...", .{});
    }
}
