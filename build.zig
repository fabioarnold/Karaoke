const std = @import("std");

const nanovg = std.build.Pkg{
    .name = "nanovg",
    .path = std.build.FileSource.relative("deps/nanovg/src/nanovg.zig"),
};

const zalgebra = std.build.Pkg{
    .name = "zalgebra",
    .path = std.build.FileSource.relative("deps/zalgebra/src/main.zig"),
};

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("Karaoke", "src/main.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);

    if (exe.target.isWindows()) {
        exe.addVcpkgPaths(.dynamic) catch @panic("vcpkg not installed");
        if (exe.vcpkg_bin_path) |bin_path| {
            const dlls = [_][]const u8{
                "SDL2.dll",
                "avcodec-58.dll",
                "avformat-58.dll",
                "avutil-56.dll",
                "swresample-3.dll",
                "swscale-5.dll",
            };
            for (dlls[0..]) |dll| {
                const src_dll = try std.fs.path.join(b.allocator, &.{ bin_path, dll });
                b.installBinFile(src_dll, dll);
            }
        }
        exe.subsystem = .Windows;
        exe.linkSystemLibrary("shell32");
        exe.addObjectFile("microphone.o"); // add icon
        exe.want_lto = false; // workaround for https://github.com/ziglang/zig/issues/8531
    }

    exe.addPackage(nanovg);
    exe.addPackage(zalgebra);

    exe.addIncludeDir("src");
    exe.addIncludeDir("src/gl2/include");
    exe.addIncludeDir("deps/nanovg/src");
    const c_flags = [_][]const u8{ "-O0", "-g", "-Werror" };
    // exe.addCSourceFile("src/myffmpeg.c", &c_flags);
    exe.addCSourceFile("src/ffplay_modified.c", &c_flags);
    exe.addCSourceFile("src/gl_render.c", &c_flags);
    exe.addCSourceFile("src/gl2/src/glad.c", &c_flags); // TODO: only on win/linux?
    exe.addCSourceFile("deps/nanovg/src/nanovg.c", &c_flags);
    exe.addCSourceFile("deps/nanovg/src/nanovg_gl2_impl.c", &c_flags);

    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("avcodec");
    // exe.linkSystemLibrary("avdevice");
    // exe.linkSystemLibrary("avfilter");
    exe.linkSystemLibrary("avformat");
    exe.linkSystemLibrary("avutil");
    exe.linkSystemLibrary("swresample");
    exe.linkSystemLibrary("swscale");
    if (exe.target.isDarwin()) {
        exe.linkFramework("OpenGL");
    } else if (exe.target.isWindows()) {
        exe.linkSystemLibrary("opengl32");
    } else if (exe.target.isLinux()) {
        exe.linkSystemLibrary("gl");
        exe.linkSystemLibrary("X11");
    }
    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
