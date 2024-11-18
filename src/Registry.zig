const std = @import("std");
const folders = @import("folders/folders.zig");
const fs = std.fs;
const path = std.fs.path;
const Backup = @import("Backup.zig");

ids: std.ArrayList(u64),
entries: std.ArrayList(Backup),
allocator: std.mem.Allocator,
stored_at: std.fs.File,

const Registry = @This();

fn makeEntriesArrayLists(
    allocator: std.mem.Allocator,
    entries: []Backup,
) !struct {
    entries: std.ArrayList(Backup),
    ids: std.ArrayList(u64),
} {
    var ids = std.ArrayList(u64).init(allocator);
    for (entries) |entry|
        try ids.append(entry.id);

    return .{
        .ids = ids,
        .entries = std.ArrayList(Backup).fromOwnedSlice(allocator, entries),
    };
}

const json_serialize_options: std.json.StringifyOptions = .{
    .whitespace = .indent_2,
    .escape_unicode = true,
    .emit_strings_as_arrays = false,
    .emit_null_optional_fields = true,
    .emit_nonportable_numbers_as_strings = true,
};

fn deserializeFromDisk(
    comptime T: type,
    allocator: std.mem.Allocator,
    reader: fs.File.Reader,
) !T {
    if (reader.readByte()) |_| {
        var json_reader = std.json.reader(allocator, reader);
        var json_parsed = try std.json.parseFromTokenSource(T, allocator, &json_reader, .{
            .allocate = .alloc_if_needed,
            .max_value_len = 4096,
            .parse_numbers = true,
            .ignore_unknown_fields = false,
            .duplicate_field_behavior = .@"error",
        });

        defer {
            json_parsed.deinit();
            json_reader.deinit();
        }

        return json_parsed.value;
    } else |err| return err;
}

fn serializeToDisk(
    self: *Registry,
    allocator: std.mem.Allocator,
    writer: fs.File.Writer,
) !void {
    _ = allocator; // autofix
    var json_writer = std.json.writeStream(
        writer,
        json_serialize_options,
    );

    try json_writer.beginArray();
    for (self.entries.items) |item| {
        try json_writer.write(item);
    }
    try json_writer.endArray();
}

fn getOrCreateFileAbsolute(absolute_path: []const u8, options: fs.File.OpenFlags) !fs.File {
    std.debug.print("opening or creating: {s}", .{absolute_path});
    return fs.openFileAbsolute(absolute_path, options) catch |err| switch (err) {
        fs.File.OpenError.FileNotFound => return fs.createFileAbsolute(absolute_path, .{
            .exclusive = true,
            .truncate = false,
            .read = true,
        }),
        else => return err,
    };
}

fn getOrCreateFile(self: *fs.Dir, sub_path: []const u8, options: fs.File.OpenFlags) !fs.File {
    return self.openFile(sub_path, options) catch |err| switch (err) {
        fs.File.OpenError.FileNotFound => return self.createFile(sub_path, .{
            .exclusive = true,
            .truncate = false,
            .read = true,
        }),
        else => return err,
    };
}

pub fn init(allocator: std.mem.Allocator, options: struct {
    program_name: []const u8 = "jules-backups",
}) !Registry {
    if (try folders.getPath(allocator, .data)) |data_path| {
        const data_dir_path = try path.join(allocator, &.{ data_path, options.program_name });
        std.debug.print("\ndata_dir_path: {s}\n", .{data_dir_path});

        fs.accessAbsolute(data_dir_path, .{}) catch |err| switch (err) {
            error.FileNotFound => try fs.makeDirAbsolute(data_dir_path),
            else => {},
        };

        var data_dir = try fs.openDirAbsolute(data_dir_path, .{
            .access_sub_paths = true,
        });
        defer data_dir.close();

        var data_file = try getOrCreateFile(
            &data_dir,
            "registry.json",
            fs.File.OpenFlags{
                .lock = .exclusive,
                .mode = .read_write,
                .lock_nonblocking = true,
            },
        );

        defer data_file.close();

        const data_lists = try makeEntriesArrayLists(
            allocator,
            deserializeFromDisk(
                []Backup,
                allocator,
                data_file.reader(),
            ) catch |err| switch (err) {
                error.EndOfStream => &[_]Backup{},
                else => return err,
            },
        );

        return .{
            .ids = data_lists.ids,
            .entries = data_lists.entries,
            .allocator = allocator,
            .stored_at = data_file,
        };
    } else {
        return error.XdgDataDirNotFound;
    }
}

pub fn deinit(self: *Registry) void {
    defer self.ids.deinit();
    defer self.entries.deinit();
    try self.serializeToDisk(
        self.allocator,
        self.stored_at.writer(),
    ) catch |err| {
        _ = err; // autofix
        std.debug.print("oh fuck we couldn't serialize the backups this isn't good....", .{});
    };
}

pub fn nextId(self: *Registry) u64 {
    return self.ids.items[self.ids.items.len - 1] + 1;
}

pub fn addBackup(self: *Registry, backup: Backup) !void {
    try self.entries.append(backup);
}

pub fn getLatestBackup(self: Registry) ?Backup {
    if (self.entries.items.len == 0) return null;
    return self.entries.items[self.entries.items.len - 1];
}
