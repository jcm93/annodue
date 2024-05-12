// GAME FUNCTIONS

pub const swrSound_PlayVoiceLine: *fn (type: i32, vehicle_id: i32, sound_id: i32, pos_vec3_ptr: u32) callconv(.C) void = @ptrFromInt(0x427410);
pub const swrSound_PlaySoundSpatial: *fn (id: i32, unk2: i32, pitch: f32, vol: f32, pos: usize, unk6: i32, unk7: i32, near: f32, far: f32) callconv(.C) void = @ptrFromInt(0x426D10);
pub const swrSound_PlaySound: *fn (id: i32, unk2: i32, pitch: f32, vol: f32, unk5: i32) callconv(.C) void = @ptrFromInt(0x426C80);
pub const swrSound_PlaySoundMacro: *fn (id: i32) callconv(.C) void = @ptrFromInt(0x440550);

// GAME CONSTANTS

// ...

// HELPERS

// ...
