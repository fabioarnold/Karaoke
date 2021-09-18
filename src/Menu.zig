const std = @import("std");
const nvg = @import("nanovg");

const Song = @import("Song.zig");

songs: []Song = undefined,
song_selected: usize = 0,
select_origin: f32 = 0,
select_target: f32 = 0,
select_time: f32 = 0,
progress_alpha: f32 = 0,

font_regular: i32 = undefined,
font_bold: i32 = undefined,

const Self = @This();

pub fn loadFonts(self: *Self) !void {
    self.font_bold = nvg.createFont("regular", "data/fonts/Roboto-Bold.ttf");
    if (self.font_bold == -1) return error.FileNotFound;
    self.font_regular = nvg.createFont("bold", "data/fonts/Roboto-Regular.ttf");
    if (self.font_regular == -1) return error.FileNotFound;
    const font_emoji_path = if (std.builtin.os.tag == .windows) "C:\\Windows\\Fonts\\seguiemj.ttf" else "data/fonts/NotoEmoji-Regular.ttf";
    const font_emoji = nvg.createFont("emoji", font_emoji_path);
    if (font_emoji == -1) return error.FileNotFound;
    const font_cjk_bold = nvg.createFont("cjk", "data/fonts/NotoSansCJKjp-Bold.otf");
    _ = nvg.addFallbackFontId(self.font_regular, font_emoji);
    _ = nvg.addFallbackFontId(self.font_bold, font_emoji);
    _ = nvg.addFallbackFontId(self.font_bold, font_cjk_bold);
}

pub fn tick(self: *Self) void {
    if (self.select_time < 1) {
        self.select_time += 1.0 / 20.0;
    } else {
        self.select_time = 1;
    }
    if (self.progress_alpha > 0) self.progress_alpha -= 1.0 / 20.0;
}

pub fn prevSong(self: *Self) void {
    if (self.song_selected > 0) {
        self.song_selected -= 1;
        const select_t = easeOutQuad(self.select_time);
        self.select_origin = mix(self.select_origin, self.select_target, select_t);
        self.select_target = @intToFloat(f32, self.song_selected);
        self.select_time = 0;
    }
}

pub fn nextSong(self: *Self) void {
    if (self.song_selected + 1 < self.songs.len) {
        self.song_selected += 1;
        const select_t = easeOutQuad(self.select_time);
        self.select_origin = mix(self.select_origin, self.select_target, select_t);
        self.select_target = @intToFloat(f32, self.song_selected);
        self.select_time = 0;
    }
}

pub fn drawTitle(self: Self, width: f32, height: f32) void {
    const center_x = 0.5 * width;
    const center_y = 0.5 * height;
    const text_h = 0.3 * height;
    nvg.fontSize(text_h);
    nvg.textAlign(.{ .horizontal = .center, .vertical = .middle });
    nvg.fontFaceId(self.font_bold);
    nvg.fillColor(nvg.rgbf(1, 1, 1));
    _ = nvg.text(center_x, center_y, "カラオケ"); // カラオケ
}

pub fn drawUi(self: *Self, width: f32, height: f32) void {
    const center_x = 0.5 * width;
    const tile_h = 0.5 * height;
    const y = 0.2 * height;
    const text_y = 0.8 * height;
    const text_h = 0.05 * height;
    nvg.fontSize(text_h);

    const select_t = easeOutQuad(self.select_time);
    const select_x = mix(self.select_origin, self.select_target, select_t);
    for (self.songs) |song, i| {
        const x = center_x + (@intToFloat(f32, i) - select_x) * tile_h * 1.1 - 0.5 * tile_h;
        nvg.beginPath();
        nvg.rect(x, y, tile_h, tile_h);
        const paint = nvg.imagePattern(x, y, tile_h, tile_h, 0, song.image.?, 1);
        nvg.fillPaint(paint);
        nvg.fill();
    }

    if (self.song_selected < self.songs.len) {
        const song = self.songs[self.song_selected];
        nvg.textAlign(.{ .horizontal = .center });
        nvg.fontFaceId(self.font_bold);
        nvg.fillColor(nvg.rgbf(0, 0, 0));
        nvg.fontBlur(10);
        _ = nvg.text(center_x, text_y, song.artist);
        nvg.fontBlur(0);
        nvg.fillColor(nvg.rgbf(1, 1, 1));
        _ = nvg.text(center_x, text_y, song.artist);
        nvg.fontFaceId(self.font_regular);
        nvg.fillColor(nvg.rgbf(0, 0, 0));
        nvg.fontBlur(10);
        _ = nvg.text(center_x, text_y + 1.5 * text_h, song.title);
        nvg.fontBlur(0);
        nvg.fillColor(nvg.rgbf(1, 1, 1));
        _ = nvg.text(center_x, text_y + 1.5 * text_h, song.title);
        // _ = nvg.text(center_x, text_y + 3 * text_h, "Emojitest: 🎤🔇🔈🔉🔊🎵🎶⚙️🔧🛠️▶️");
    }

    if (self.songs.len == 0) {
        const text = "(No songs found)";
        nvg.textAlign(.{ .horizontal = .center });
        nvg.fontFaceId(self.font_regular);
        nvg.fillColor(nvg.rgbf(0, 0, 0));
        nvg.fontBlur(10);
        _ = nvg.text(center_x, text_y + 1.5 * text_h, text);
        nvg.fontBlur(0);
        nvg.fillColor(nvg.rgbf(1, 1, 1));
        _ = nvg.text(center_x, text_y + 1.5 * text_h, text);
    }
}

pub fn drawPauseUi(self: *Self, width: f32, height: f32) void {
    _ = self;
    nvg.beginPath();
    nvg.rect(0, 0, width, height);
    nvg.fillColor(nvg.rgbaf(0, 0, 0, 0.5));
    nvg.fill();

    const text_h = 0.05 * height;
    nvg.fontSize(text_h);
    const center_x = 0.5 * width;
    const center_y = 0.5 * height;
    nvg.textAlign(.{ .horizontal = .center });
    nvg.fontFaceId(self.font_bold);
    nvg.fillColor(nvg.rgbf(0, 0, 0));
    nvg.fontBlur(10);
    _ = nvg.text(center_x, center_y, "- Pause -");
    nvg.fontBlur(0);
    nvg.fillColor(nvg.rgbf(1, 1, 1));
    _ = nvg.text(center_x, center_y, "- Pause -");
}

pub fn drawProgress(self: *Self, width: f32, height: f32, progress: f32) void {
    const a = std.math.clamp(self.progress_alpha, 0, 1);
    nvg.beginPath();
    const f = 0.01 * height;
    const x = 0.1 * width;
    const y = 0.9 * height;
    const w = 0.8 * width;
    const h = 0.04 * height;
    nvg.rect(x - f, y - f, w + 2 * f, h + 2 * f);
    nvg.pathWinding(.cw);
    nvg.roundedRect(x, y, w, h, 0.5 * h);
    nvg.pathWinding(.ccw);
    nvg.fillPaint(nvg.boxGradient(x - 0.5 * f, y - 0.5 * f, w + f, h + f, 0.5 * h, f, nvg.rgbaf(0, 0, 0, 0.25 * a), nvg.rgbaf(0, 0, 0, 0)));
    nvg.fill();
    {
        nvg.scissor(x + w * progress, y, w * (1 - progress), h);
        defer nvg.resetScissor();
        nvg.beginPath();
        nvg.roundedRect(x, y, w, h, 0.5 * h);
        nvg.fillColor(nvg.rgbaf(0.5, 0.5, 0.5, a));
        nvg.fill();
    }
    {
        nvg.scissor(x, y, w * progress, h);
        defer nvg.resetScissor();
        nvg.beginPath();
        nvg.roundedRect(x, y, w, h, 0.5 * h);
        nvg.fillColor(nvg.rgbaf(1, 1, 1, a));
        nvg.fill();
    }
}

fn easeOutQuad(x: f32) f32 {
    return 1 - (1 - x) * (1 - x);
}

fn mix(a: f32, b: f32, t: f32) f32 {
    return (1 - t) * a + t * b;
}
