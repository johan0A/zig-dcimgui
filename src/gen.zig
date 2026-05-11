const std = @import("std");

pub const Backend = enum {
    imgui_impl_allegro5,
    imgui_impl_android,
    imgui_impl_dx10,
    imgui_impl_dx11,
    imgui_impl_dx12,
    imgui_impl_dx9,
    imgui_impl_glfw,
    imgui_impl_glut,
    imgui_impl_null,
    imgui_impl_opengl2,
    imgui_impl_opengl3,
    imgui_impl_opengl3_loader,
    imgui_impl_sdl2,
    imgui_impl_sdl3,
    imgui_impl_sdlgpu3,
    imgui_impl_sdlgpu3_shaders,
    imgui_impl_sdlrenderer2,
    imgui_impl_sdlrenderer3,
    imgui_impl_vulkan,
    imgui_impl_wgpu,
    imgui_impl_win32,
    // imgui_impl_metal, // unsupported
    // imgui_impl_osx, // unsupported
};

const Args = struct {
    python_path: []const u8,
    generator_path: []const u8,
    out_path: []const u8,
    imgui_path: []const u8,
};

fn run(io: std.Io, argv: []const []const u8, node: std.Progress.Node) error{Canceled}!void {
    defer node.end();
    runInner(io, argv) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => {
            std.log.err("task failed ({s}): {s}", .{ argv[0], @errorName(err) });
        },
    };
}

fn runInner(io: std.Io, argv: []const []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    _ = try child.wait(io);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const raw_args = try init.minimal.args.toSlice(arena);

    if (raw_args.len < 5) {
        std.debug.print("Usage: {s} <python_path> <generator_path> <out_path> <path>\n", .{raw_args[0]});
        std.process.exit(1);
    }

    const args: Args = .{
        .python_path = raw_args[1],
        .generator_path = raw_args[2],
        .out_path = raw_args[3],
        .imgui_path = raw_args[4],
    };

    try std.Io.Dir.cwd().deleteTree(io, args.out_path);

    const progress = std.Progress.start(io, .{ .root_name = "gen" });
    defer progress.end();

    var group: std.Io.Group = .init;
    defer group.cancel(io);

    try std.Io.Dir.cwd().createDir(io, args.out_path, .default_dir);
    {
        const argv = try arena.dupe([]const u8, &.{
            args.python_path,
            args.generator_path,
            try std.fs.path.join(arena, &.{ args.imgui_path, "imgui.h" }),

            "-o",
            try std.fs.path.join(arena, &.{ args.out_path, "dcimgui" }),
        });

        group.async(io, run, .{ io, argv, progress.start("dcimgui", 0) });
    }

    const backends_out_path = try std.fs.path.join(arena, &.{ args.out_path, "backends" });
    try std.Io.Dir.createDirAbsolute(io, backends_out_path, .default_dir);

    for (std.enums.values(Backend)) |field| {
        const argv = try arena.dupe([]const u8, &.{
            args.python_path,
            args.generator_path,
            "--backend",

            "--include",
            try std.fs.path.join(arena, &.{ args.imgui_path, "imgui.h" }),

            try std.fmt.allocPrint(arena, "{s}/{s}/{s}.h", .{ args.imgui_path, "backends", @tagName(field) }),

            "-o",
            try std.fmt.allocPrint(arena, "{s}/dc{s}", .{ backends_out_path, @tagName(field) }),
        });

        const node_name = try std.fmt.allocPrint(arena, "backend {t}", .{field});
        group.async(io, run, .{ io, argv, progress.start(node_name, 0) });
    }

    try group.await(io);

    var out_dir = try std.Io.Dir.openDirAbsolute(io, args.out_path, .{ .iterate = true });
    defer out_dir.close(io);

    var walk = try out_dir.walk(arena);
    defer walk.deinit();

    while (try walk.next(io)) |entry| {
        if (std.mem.eql(u8, std.fs.path.extension(entry.basename), ".json")) {
            try out_dir.deleteFile(io, entry.path);
        }
    }
}
