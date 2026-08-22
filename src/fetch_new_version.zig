const std = @import("std");

fn fetch(io: std.Io, arena: std.mem.Allocator, name: []const u8, link: []const u8) !void {
    const args: []const []const u8 = &.{
        "zig",
        "fetch",
        try std.fmt.allocPrint(arena, "--save={s}", .{name}),
        link,
    };
    std.debug.print("running: ", .{});
    for (args) |arg| std.debug.print("{s} ", .{arg});
    std.debug.print("\n", .{});
    const result = try std.process.run(arena, io, .{ .argv = args });
    if (result.term != .exited or result.term.exited != 0) {
        std.debug.print("{s}\n", .{result.stderr});
        return error.CommandFailed;
    }
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const imgui_version = args[1];
    const dear_bindings_version = args[2];

    try fetch(init.io, arena, "dear_bindings", try std.fmt.allocPrint(
        arena,
        "git+https://github.com/dearimgui/dear_bindings#DearBindings_{s}_ImGui_{s}",
        .{ dear_bindings_version, imgui_version },
    ));
    try fetch(init.io, arena, "dear_bindings_docking", try std.fmt.allocPrint(
        arena,
        "git+https://github.com/dearimgui/dear_bindings#DearBindings_{s}_ImGui_{s}-docking",
        .{ dear_bindings_version, imgui_version },
    ));

    try fetch(init.io, arena, "imgui", try std.fmt.allocPrint(
        arena,
        "git+https://github.com/ocornut/imgui#{s}",
        .{imgui_version},
    ));
    try fetch(init.io, arena, "imgui_docking", try std.fmt.allocPrint(
        arena,
        "git+https://github.com/ocornut/imgui#{s}-docking",
        .{imgui_version},
    ));
}
