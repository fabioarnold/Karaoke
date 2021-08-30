const ORG_NAME = "FabioWare";
const APP_NAME = "Karaoke";

const std = @import("std");
const c = @cImport({
    @cInclude("video.h");
    @cInclude("glad/glad.h");
});
const nvg = @import("nanovg");
const gl = @import("zgl.zig");
const za = @import("zalgebra");

const Menu = @import("Menu.zig");
const Song = @import("Song.zig");

extern fn SetProcessDPIAware() callconv(.C) c_int; // enable High DPI on Windows

const FF_QUIT_EVENT = c.SDL_USEREVENT + 2; // is generated when ffplay encounters an error
const SDL_AUDIO_MIN_BUFFER_SIZE = 512; // Minimum SDL audio buffer size, in samples.
// Calculate actual buffer size keeping in mind not cause too frequent audio callbacks
const SDL_AUDIO_MAX_CALLBACKS_PER_SEC = 30;

var program: gl.Program = undefined;
var mvp_loc: u32 = undefined;
var window: ?*c.SDL_Window = null;
var audio_dev: c.SDL_AudioDeviceID = 0;
var audio_input_dev: c.SDL_AudioDeviceID = 0;
var path_buf: [2048]u8 = undefined;
var buf: [0x1000]u8 = undefined;

const AppData = struct {
    const State = enum { intro, menu, play, pause };

    const Settings = struct {
        window_width: i32 = 0, // <= 0 means undefined, let app choose
        window_height: i32 = 0,
        fullscreen: bool = true,
        audio_input_enabled: bool = true,
        volume: f32 = 0.5, // 0-1
        show_intro: bool = false,

        fn load(self: *Settings, pref_path: []const u8) !void {
            var allocator = &std.heap.FixedBufferAllocator.init(&buf).allocator;
            const filepath = try std.fs.path.join(allocator, &.{ pref_path, "settings.json" });
            defer allocator.free(filepath);
            const file = try std.fs.cwd().openFile(filepath, .{});
            defer file.close();
            const len = try file.readAll(&buf);
            var stream = std.json.TokenStream.init(buf[0..len]);
            self.* = try std.json.parse(Settings, &stream, .{ .allocator = allocator, .ignore_unknown_fields = true });
        }

        fn write(self: Settings, pref_path: []const u8) !void {
            var allocator = &std.heap.FixedBufferAllocator.init(&buf).allocator;
            const filepath = try std.fs.path.join(allocator, &.{ pref_path, "settings.json" });
            defer allocator.free(filepath);
            var file = try std.fs.cwd().createFile(filepath, .{});
            defer file.close();
            try std.json.stringify(self, .{}, file.writer());
        }
    };

    settings: Settings = Settings{},
    menu: Menu = Menu{},
    state: State = .intro,
    intro_duration: f32 = 9,
    quit: bool = false,
    video_background: ?*c.VideoState = null,
    video_song: ?*c.VideoState = null,
    vc: ?*c.VideoContext = null,

    fn load(app: *AppData, allocator: *std.mem.Allocator, pref_path: []const u8) !void {
        app.menu.songs = try Song.loadSongs(allocator, pref_path);
        for (app.menu.songs) |*song| {
            const filepath = try allocator.dupeZ(u8, song.album_art);
            defer allocator.free(filepath);
            song.image = nvg.createImage(filepath, .{});
        }

        try app.menu.loadFonts();

        if (app.settings.show_intro) {
            app.state = .intro;
            app.video_background = c.stream_open("data/intro.mp4", app.vc) orelse return error.StreamOpenFail;
        } else {
            app.state = .menu;
            app.video_background = c.stream_open("data/background.mov", app.vc) orelse return error.StreamOpenFail;
            c.video_set_looping(app.video_background, 1);
        }
    }

    fn free(app: *AppData, allocator: *std.mem.Allocator) void {
        for (app.menu.songs) |song| song.free(allocator);
        allocator.free(app.menu.songs);

        if (app.video_background) |video| {
            app.video_background = null;
            c.stream_close(video);
        }
        if (app.video_song) |video| {
            app.video_song = null;
            c.stream_close(video);
        }
    }

    fn onEscapePressed(app: *AppData) void {
        switch (app.state) {
            .intro => {},
            .menu => app.quit = true,
            .play => {
                c.video_set_paused(app.video_song, 1);
                app.state = .pause;
            },
            .pause => {
                // close video
                if (app.video_song) |video| {
                    app.video_song = null;
                    c.SDL_LockAudioDevice(audio_dev);
                    defer c.SDL_UnlockAudioDevice(audio_dev);
                    c.stream_close(video);
                }
                c.video_set_paused(app.video_background, 0); // continue background video
                app.state = .menu;
            },
        }
    }

    fn onLeftPressed(app: *AppData) void {
        switch (app.state) {
            .intro => {},
            .menu => app.menu.prevSong(),
            .play, .pause => {
                var pos = c.video_get_position(app.video_song);
                pos = std.math.max(0, pos - 10.0);
                c.video_stream_seek(app.video_song, @floatToInt(i64, pos * 1_000_000));
                app.menu.progress_alpha = 5;
            },
        }
    }

    fn onRightPressed(app: *AppData) void {
        switch (app.state) {
            .intro => {},
            .menu => app.menu.nextSong(),
            .play, .pause => {
                var pos = c.video_get_position(app.video_song);
                pos += 10.0;
                c.video_stream_seek(app.video_song, @floatToInt(i64, pos * 1_000_000));
                app.menu.progress_alpha = 5;
            },
        }
    }

    fn onReturnPressed(app: *AppData) !void {
        switch (app.state) {
            .intro => {},
            .menu => {
                if (app.menu.song_selected < app.menu.songs.len) {
                    c.video_set_paused(app.video_background, 1);
                    const song = app.menu.songs[app.menu.song_selected];
                    var allocator = &std.heap.FixedBufferAllocator.init(&path_buf).allocator;
                    const filepath = try allocator.dupeZ(u8, song.video);
                    defer allocator.free(filepath);
                    app.video_song = c.stream_open(filepath, app.vc) orelse return error.StreamOpenFail;
                    //c.video_stream_seek(app.video_song, (3 * 60 + 52) * 1_000_000); // TEST: seek to end
                    c.video_set_volume(app.video_song, app.settings.volume);
                    app.state = .play;
                }
            },
            .play => {
                c.video_set_paused(app.video_song, 1);
                app.state = .pause;
            },
            .pause => {
                c.video_set_paused(app.video_song, 0);
                app.state = .play;
            },
        }
    }

    fn draw(app: *AppData) void {
        var window_width: i32 = undefined;
        var window_height: i32 = undefined;
        c.SDL_GetWindowSize(window, &window_width, &window_height);
        gl.viewport(0, 0, @intCast(u32, window_width), @intCast(u32, window_height));

        const width: f32 = @intToFloat(f32, window_width);
        const height = @intToFloat(f32, window_height);
        const window_ar = width / height;

        gl.clearColor(0, 0, 0, 1);
        gl.clear(.{ .color = true, .stencil = true });

        var video_width: i32 = undefined;
        var video_height: i32 = undefined;

        const proj = za.perspective(45.0, window_ar, 0.1, 100.0);
        const view = za.lookAt(za.Vec3.new(0, 0, 3), za.Vec3.zero(), za.Vec3.up());
        _ = proj;
        _ = view;

        if (app.state == .intro or app.state == .menu) {
            // background video
            if (app.video_background) |video| {
                c.video_update(video);
                c.video_get_dims(video, &video_width, &video_height);
                const video_ar = @intToFloat(f32, video_width) / @intToFloat(f32, video_height);
                // const model = za.Mat4.fromScale(za.Vec3.new(video_ar, 1, 1)).rotate(45 + 15 * std.math.sin(select_time * 2.3), za.Vec3.new(0, 1, 0)).translate(za.Vec3.new(-1, 0, 0));
                // const mvp = proj.mult(view).mult(model);

                const s = video_ar / window_ar;
                const sx = std.math.max(1, s);
                const sy = std.math.max(1, 1 / s);
                const mvp = za.Mat4.fromScale(za.Vec3.new(sx, sy, 1));

                c.video_bind_texture(video);
                program.uniformMatrix4(mvp_loc, false, &.{mvp.data});
                c.glRectf(-1, -1, 1, 1);

                // handle end of intro video
                if (app.state == .intro) {
                    if (c.video_is_finished(video) != 0) {
                        app.video_background = null;
                        c.stream_close(video);
                    }
                }
            }
        }

        if (app.state == .intro) {
            app.intro_duration -= 1.0 / 60.0;
            if (app.intro_duration <= 0) {
                app.state = .menu;
                app.video_background = c.stream_open("data/background.mov", app.vc) orelse null;
                if (app.video_background != null) c.video_set_looping(app.video_background, 1);
            }
        }

        var progress: f32 = 0;
        if (app.state == .play or app.state == .pause) {
            if (app.video_song) |video| {
                c.video_update(video);
                const pos = c.video_get_position(video);
                const dur = c.video_get_duration(video);
                if (dur > 0) {
                    progress = std.math.clamp(@floatCast(f32, pos / dur), 0, 1);
                }
                c.video_get_dims(video, &video_width, &video_height);
                const video_ar = @intToFloat(f32, video_width) / @intToFloat(f32, video_height);
                // const model = za.Mat4.fromScale(za.Vec3.new(video_ar, 1, 1)).rotate(-45 + 15 * std.math.sin(select_time * 1.3), za.Vec3.new(0, 1, 0)).translate(za.Vec3.new(1, 0, 0));
                // const mvp = proj.mult(view).mult(model);

                const s = video_ar / window_ar;
                const sx = std.math.max(1, s);
                const sy = std.math.max(1, 1 / s);
                const mvp = za.Mat4.fromScale(za.Vec3.new(sx, sy, 1));

                c.video_bind_texture(video);
                program.uniformMatrix4(mvp_loc, false, &.{mvp.data});
                c.glRectf(-1, -1, 1, 1);

                // handle end of video
                if (c.video_is_finished(video) != 0) {
                    app.video_song = null;
                    c.stream_close(video);
                    app.state = .menu;
                    c.video_set_paused(app.video_background, 0);
                }
            }
        }

        // draw 2D UI
        nvg.beginFrame(width, height, 1); // TODO: pixel scale
        switch (app.state) {
            .intro => {
                if (app.video_background == null) {
                    app.menu.drawTitle(width, height);
                }
            },
            .menu => app.menu.drawUi(width, height),
            .play => app.menu.drawProgress(width, height, progress),
            .pause => {
                app.menu.drawPauseUi(width, height);
                app.menu.progress_alpha = 1; // always visible
                app.menu.drawProgress(width, height, progress);
            },
        }
        nvg.endFrame();

        c.SDL_GL_SwapWindow(window);
    }
};

fn initGl() void {
    program = gl.Program.create();
    {
        const vs = gl.Shader.create(.vertex);
        defer vs.delete();
        vs.source(1, &.{@embedFile("shaders/yuv.vert")});
        vs.compile();
        const fs = gl.Shader.create(.fragment);
        defer fs.delete();
        fs.source(1, &.{@embedFile("shaders/yuv.frag")});
        fs.compile();
        program.attach(vs);
        defer program.detach(vs);
        program.attach(fs);
        defer program.detach(fs);
        program.link();
    }
    program.use();
    mvp_loc = program.uniformLocation("mvp").?;
    if (program.uniformLocation("tex0")) |tex0| program.uniform1i(tex0, 0);
    if (program.uniformLocation("tex1")) |tex1| program.uniform1i(tex1, 1);
    if (program.uniformLocation("tex2")) |tex2| program.uniform1i(tex2, 2);
}

fn sdlAudioCallback(userdata: ?*c_void, stream: [*c]u8, len: c_int) callconv(.C) void {
    const queue_len = c.SDL_GetQueuedAudioSize(audio_input_dev);
    if (queue_len >= len and len > 0) {
        const dequeued_len = c.SDL_DequeueAudio(audio_input_dev, stream, @intCast(c_uint, len));
        if (queue_len > 3 * len) { // avoid too much latency
            c.SDL_ClearQueuedAudio(audio_input_dev);
            std.log.warn("clearing queued audio", .{});
        }
        _ = dequeued_len;
        //std.log.info("dequeued {} bytes", .{dequeued_len});
    } else {
        std.mem.set(u8, stream[0..@intCast(usize, len)], 0); // silence
    }

    var app_data = @ptrCast(*AppData, @alignCast(@alignOf(*AppData), userdata.?));
    if (app_data.video_background) |video| c.video_sdl_audio_callback(video, stream, len);
    if (app_data.video_song) |video| c.video_sdl_audio_callback(video, stream, len);
}

fn sdlIsFullscreen() bool {
    return c.SDL_GetWindowFlags(window) & c.SDL_WINDOW_FULLSCREEN_DESKTOP != 0;
}

fn sdlToggleFullscreen() void {
    if (sdlIsFullscreen()) {
        _ = c.SDL_SetWindowFullscreen(window, 0);
        _ = c.SDL_ShowCursor(1);
    } else {
        _ = c.SDL_SetWindowFullscreen(window, c.SDL_WINDOW_FULLSCREEN_DESKTOP);
        _ = c.SDL_ShowCursor(0);
    }
}

fn sdlEventWatch(userdata: ?*c_void, sdl_event_ptr: [*c]c.SDL_Event) callconv(.C) c_int {
    var app_data = @ptrCast(*AppData, @alignCast(@alignOf(*AppData), userdata.?));
    if (app_data.quit) return 1;
    const sdl_event = sdl_event_ptr[0];
    if (sdl_event.type == c.SDL_WINDOWEVENT) {
        if (sdl_event.window.event == c.SDL_WINDOWEVENT_RESIZED) {
            app_data.draw();
            return 0;
        }
    }
    return 1; // unhandled
}

fn eventLoop(app: *AppData) !void {
    while (!app.quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_ESCAPE => app.onEscapePressed(),
                        c.SDLK_LEFT => app.onLeftPressed(),
                        c.SDLK_RIGHT => app.onRightPressed(),
                        c.SDLK_RETURN => try app.onReturnPressed(),
                        c.SDLK_F11, c.SDLK_f => sdlToggleFullscreen(),
                        else => {},
                    }
                },
                c.SDL_QUIT, FF_QUIT_EVENT => app.quit = true,
                else => {},
            }
        }

        app.menu.tick();
        app.draw();
    }
}

pub fn main() anyerror!void {
    // enable High DPI on Windows
    if (std.builtin.os.tag == .windows) _ = SetProcessDPIAware();

    var gpa = std.heap.GeneralPurposeAllocator(.{
        .enable_memory_limit = true,
    }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked) @panic("Memory leak :(");
    }
    const allocator = &gpa.allocator;

    var app_data = AppData{};

    const flags = c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO;
    if (c.SDL_Init(flags) != 0) {
        std.log.crit("SDL_Init failed: {s}", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_Quit();

    const sdl_pref_path = c.SDL_GetPrefPath(ORG_NAME, APP_NAME);
    if (sdl_pref_path == null) {
        std.log.crit("SDL_GetPrefPath failed: {s}", .{c.SDL_GetError()});
        return;
    }
    const pref_path = std.mem.sliceTo(sdl_pref_path, 0);

    app_data.settings.load(pref_path) catch {}; // ignore

    _ = c.SDL_GL_SetAttribute(c.SDL_GL_STENCIL_SIZE, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLEBUFFERS, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLESAMPLES, 4);
    const window_x: c_int = @bitCast(c_int, c.SDL_WINDOWPOS_UNDEFINED);
    const window_y: c_int = @bitCast(c_int, c.SDL_WINDOWPOS_UNDEFINED);
    var display_mode: c.SDL_DisplayMode = undefined;
    _ = c.SDL_GetDesktopDisplayMode(0, &display_mode);
    var window_width: c_int = @divTrunc(display_mode.w * 3, 4);
    var window_height: c_int = @divTrunc(display_mode.h * 3, 4);
    if (app_data.settings.window_width > 0) window_width = app_data.settings.window_width;
    if (app_data.settings.window_height > 0) window_height = app_data.settings.window_height;
    var window_flags: u32 = c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_HIDDEN;
    if (app_data.settings.fullscreen) {
        window_flags |= c.SDL_WINDOW_FULLSCREEN_DESKTOP;
        _ = c.SDL_ShowCursor(0);
    }
    window = c.SDL_CreateWindow("Karaoke", window_x, window_y, window_width, window_height, window_flags);
    if (window == null) {
        std.log.crit("SDL_CreateWindow failed: {s}", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_DestroyWindow(window);

    defer {
        app_data.settings.fullscreen = sdlIsFullscreen();
        if (!app_data.settings.fullscreen) {
            c.SDL_GetWindowSize(window, &app_data.settings.window_width, &app_data.settings.window_height);
        }
        app_data.settings.write(pref_path) catch {}; // ignore
    }

    var gl_context = c.SDL_GL_CreateContext(window);
    defer c.SDL_GL_DeleteContext(gl_context);
    _ = c.SDL_GL_SetSwapInterval(1); // vsync

    c.SDL_AddEventWatch(sdlEventWatch, &app_data);

    _ = c.gladLoadGL(); // load OpenGL functions
    initGl();

    nvg.init();
    defer nvg.quit();

    // audio specs containers
    var wanted_specs: c.SDL_AudioSpec = undefined;
    var specs: c.SDL_AudioSpec = undefined;

    // set audio settings
    wanted_specs.freq = 44100;
    wanted_specs.format = c.AUDIO_S16SYS;
    wanted_specs.channels = 2;
    wanted_specs.silence = 0;
    // copied from ffplay
    const exp = std.math.log2_int(u16, @intCast(u16, @intCast(u32, wanted_specs.freq) / SDL_AUDIO_MAX_CALLBACKS_PER_SEC));
    wanted_specs.samples = std.math.max(SDL_AUDIO_MIN_BUFFER_SIZE, @as(u16, 2) << exp);
    wanted_specs.callback = sdlAudioCallback;
    wanted_specs.userdata = &app_data;

    // open audio output device
    const allowed_changes = c.SDL_AUDIO_ALLOW_FREQUENCY_CHANGE; // | c.SDL_AUDIO_ALLOW_FORMAT_CHANGE;
    audio_dev = c.SDL_OpenAudioDevice(null, 0, &wanted_specs, &specs, allowed_changes);
    if (audio_dev == 0) return error.OpenAudioDeviceFail;
    defer c.SDL_CloseAudioDevice(audio_dev);

    app_data.vc = c.video_init(specs.freq, specs.channels, specs.size) orelse return error.VideoInitFailed;
    defer c.video_quit(app_data.vc);

    // open audio input device
    if (app_data.settings.audio_input_enabled) {
        wanted_specs.freq = specs.freq;
        wanted_specs.callback = null; // use sdl queue
        audio_input_dev = c.SDL_OpenAudioDevice(null, 1, &wanted_specs, &specs, 0);
        if (audio_input_dev != 0) {
            std.log.info("audio input device: {s}", .{c.SDL_GetAudioDeviceName(0, 1)});
        }
    }
    defer c.SDL_CloseAudioDevice(audio_input_dev);

    try app_data.load(allocator, pref_path);
    defer app_data.free(allocator);

    c.SDL_PauseAudioDevice(audio_input_dev, 0); // start recording
    defer c.SDL_PauseAudioDevice(audio_input_dev, 1); // stop

    c.SDL_PauseAudioDevice(audio_dev, 0); // play audio
    defer c.SDL_PauseAudioDevice(audio_dev, 1); // stop

    c.SDL_ShowWindow(window);

    try eventLoop(&app_data);
}
