const std = @import("std");

id: u64,
timestamp: i64,
filename: []const u8,
size_bytes: u64,
source_path: []const u8,

const Backup = @This();

pub fn serialize(self: *Backup, writer: anytype) !void {
    return std.json.stringify(
        self,
        .{
            .whitespace = .indent_2,
            .escape_unicode = true,
            .emit_strings_as_arrays = false,
            .emit_null_optional_fields = true,
            .emit_nonportable_numbers_as_strings = true,
        },
        writer,
    );
}
