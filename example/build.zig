const std = @import("std");
const dcimgui = @import("dcimgui");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    {
        const sdl_dep = b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
            .preferred_link_mode = .static,
        });
        root_module.linkLibrary(sdl_dep.artifact("SDL3"));

        const cimgui_dep = b.dependency("dcimgui", .{
            .target = target,
            .optimize = optimize,
            .docking = true,
            .backends = &[_]dcimgui.Backend{ .imgui_impl_sdlrenderer3, .imgui_impl_sdl3 },
            .@"include-path-list" = &[_]std.Build.LazyPath{sdl_dep.artifact("SDL3").getEmittedIncludeTree()},
            .imconfig = b.addWriteFiles().add("imconfig.h",
                \\ #pragma once
                \\ #define IMGUI_DEBUG_PARANOID 
            ),
        });
        root_module.linkLibrary(cimgui_dep.artifact("dcimgui"));

        const translate_c = b.addTranslateC(.{
            .root_source_file = b.addWriteFiles().add("stub.h",
                \\#include <SDL3/SDL.h>
                \\#include <dcimgui.h>
                \\#include <dcimgui_impl_sdl3.h>
                \\#include <dcimgui_impl_sdlrenderer3.h>
            ),
            .target = target,
            .optimize = optimize,
        });
        translate_c.addIncludePath(sdl_dep.artifact("SDL3").getEmittedIncludeTree());
        translate_c.addIncludePath(cimgui_dep.artifact("dcimgui").getEmittedIncludeTree());
        root_module.addImport("c", translate_c.createModule());
    }

    {
        const exe = b.addExecutable(.{
            .name = "example",
            .root_module = root_module,
        });
        b.installArtifact(exe);
        exe.subsystem = .Windows;

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
}
