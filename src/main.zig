const std = @import("std");
const Registry = @import("Registry.zig");
const folders = @import("folders/folders.zig");
const fs = std.fs;
const path = std.fs.path;

const Config = struct {
    target: []const u8,
    destination: []const u8,
    exclude: []const []const u8,
    retention: u32,
};

pub fn createBackup(
    allocator: std.mem.Allocator,
    options: Config,
    progress_node: std.Progress.Node,
) !void {
    _ = progress_node;

    if (!path.isAbsolute(options.destination) or !path.isAbsolute(options.target))
        return error.RelativePathUnsupported;

    var registry = try Registry.init(allocator, .{});
    defer registry.deinit();

    std.debug.print("{any}", .{registry.entries.items});

    std.debug.print("Checking destination dir: `{s}`...", .{options.destination});

    var dest_dir = try std.fs.openDirAbsolute(options.destination, .{
        .access_sub_paths = true,
    });

    var target_dir = try std.fs.openDirAbsolute(options.target, .{
        .iterate = true,
        .access_sub_paths = true,
    });

    defer {
        dest_dir.close();
        target_dir.close();
    }

    // Get current timestamp for backup name
    const timestamp = std.time.timestamp();
    const backup_name = try std.fmt.allocPrint(
        allocator,
        "backup_{d}.tar.gz",
        .{timestamp},
    );
    _ = backup_name; // autofix

    var rsync_args = std.ArrayList([]const u8).init(allocator);
    defer rsync_args.deinit();

    try rsync_args.appendSlice(&[_][]const u8{
        "rsync",
        "-av", // archive mode and verbose
    });

    for (options.exclude) |exclude_pattern| {
        const exclude_arg = try std.fmt.allocPrint(
            allocator,
            "--exclude={s}",
            .{exclude_pattern},
        );
        try rsync_args.append(exclude_arg);
    }
}

fn runCommand(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    cwd: ?*std.fs.Dir,
    progress_node: std.Progress.Node,
) !void {
    const res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd_dir = if (cwd) |dir| dir.* else std.fs.cwd(),
        .progress_node = progress_node,
    });

    if (res.stderr.len > 0) {
        std.debug.print("stderr: {s}\n", .{res.stderr});
    }

    if (res.stdout.len > 0) {
        std.debug.print("stdout: {s}\n", .{res.stdout});
    }

    switch (res.term) {
        .Exited => |code| {
            if (code != 0) {
                return error.CommandFailed;
            }
        },
        else => return error.CommandFailed,
    }
}

pub fn main() !void {
    const time = std.time.timestamp();
    std.debug.print("{}", .{time});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const progress = std.Progress.start(.{
        .root_name = "Initializing backup...",
        .estimated_total_items = 10,
    });

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (try folders.getPath(allocator, .home)) |home_path| {
        const config = Config{
            .target = home_path,
            .destination = "/mnt/000_kingston_500G/000_backups/",
            .retention = 5,
            .exclude = &[_][]const u8{
                ".cache/",
                "node_modules/",
                ".git/",
                "*.log",
                ".zig-cache",
                ".local/share/Trash/",
            },
        };

        try createBackup(allocator, config, progress.start("Running backup....", 4));
    } else {
        return error.XdgHomeNotFound;
    }
}
