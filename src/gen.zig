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
    generator_path: []const u8,
    out_path: []const u8,
    imgui_path: []const u8,
};

fn run(proc: std.process.Child, node: std.Progress.Node) !void {
    var proc_var = proc;
    proc_var.stderr_behavior = .Ignore;
    proc_var.stdout_behavior = .Ignore;
    _ = try proc_var.spawn();
    try proc_var.waitForSpawn();
    _ = try proc_var.wait();
    node.end();
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    const raw_args = try std.process.argsAlloc(gpa);

    if (raw_args.len < 4) {
        std.debug.print("Usage: {s} <generator_path> <out_path> <path>\n", .{raw_args[0]});
        return;
    }

    const args: Args = .{
        .generator_path = raw_args[1],
        .out_path = raw_args[2],
        .imgui_path = raw_args[3],
    };

    std.fs.deleteTreeAbsolute(args.out_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    };

    const python_path = "python";

    const progress = std.Progress.start(.{ .root_name = "gen" });
    defer progress.end();

    var procs: std.ArrayList(std.Thread) = .empty;

    {
        try std.fs.makeDirAbsolute(args.out_path);
        const argv = try gpa.dupe([]const u8, &.{
            python_path,
            args.generator_path,
            try std.fs.path.join(gpa, &.{ args.imgui_path, "imgui.h" }),

            "-o",
            try std.fs.path.join(gpa, &.{ args.out_path, "dcimgui" }),
        });
        const proc: std.process.Child = .init(argv, gpa);

        const thread = try std.Thread.spawn(.{}, run, .{ proc, progress.start("dcimgui", 0) });
        try procs.append(gpa, thread);
    }

    const backends_out_path = try std.fs.path.join(gpa, &.{ args.out_path, "backends" });
    try std.fs.makeDirAbsolute(backends_out_path);
    for (std.enums.values(Backend)) |field| {
        const argv = try gpa.dupe([]const u8, &.{
            python_path,
            args.generator_path,
            "--backend",

            "--include",
            try std.fs.path.join(gpa, &.{ args.imgui_path, "imgui.h" }),

            try std.fmt.allocPrint(gpa, "{s}/{s}/{s}.h", .{ args.imgui_path, "backends", @tagName(field) }),

            "-o",
            try std.fmt.allocPrint(gpa, "{s}/dc{s}", .{ backends_out_path, @tagName(field) }),
        });
        const proc: std.process.Child = .init(argv, gpa);

        const node_name = try std.fmt.allocPrint(gpa, "backend {t}", .{field});
        const thread = try std.Thread.spawn(.{}, run, .{ proc, progress.start(node_name, 0) });
        try procs.append(gpa, thread);
    }

    for (procs.items) |*proc| {
        proc.join();
    }

    const out_dir = try std.fs.openDirAbsolute(args.out_path, .{ .iterate = true });
    var walk = try out_dir.walk(gpa);
    while (try walk.next()) |entry| {
        if (std.mem.eql(u8, std.fs.path.extension(entry.basename), ".json")) {
            try out_dir.deleteFile(entry.path);
        }
    }
}

const std = @import("std");
