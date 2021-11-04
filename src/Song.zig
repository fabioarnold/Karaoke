const std = @import("std");
const nvg = @import("nanovg");

title: []const u8,
artist: []const u8,
album_art: []const u8,
video: []const u8,
image: ?nvg.Image = null,

const Self = @This();
const Song = Self;

pub fn loadSongs(allocator: std.mem.Allocator, pref_path: []const u8) ![]Song {
    var arr = std.ArrayList(Song).init(allocator);
    defer arr.deinit();
    const buf = try allocator.alloc(u8, 0x1000); // json can't be larger than 64k
    defer allocator.free(buf);

    const user_songs_path = try std.fs.path.join(allocator, &.{ pref_path, "songs" });
    defer allocator.free(user_songs_path);
    for ([_][]const u8{ "songs", user_songs_path }) |songs_path| {
        const songs_dir = std.fs.cwd().openDir(songs_path, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.FileNotFound => continue, // skip dir
                else => return err,
            }
        };
        var dir_it = songs_dir.iterate();
        while (try dir_it.next()) |entry| {
            if (entry.kind != .File) continue;
            const file_ext = std.fs.path.extension(entry.name);
            if (std.ascii.eqlIgnoreCase(".json", file_ext)) {
                const file = try songs_dir.openFile(entry.name, .{});
                defer file.close();
                const len = try file.readAll(buf);
                var stream = std.json.TokenStream.init(buf[0..len]);
                var song = try std.json.parse(Song, &stream, .{ .allocator = allocator, .ignore_unknown_fields = true });
                try song.resolvePaths(allocator, songs_path);
                try arr.append(song);
            }
        }
    }

    // sort songs by artist, title asc
    std.sort.sort(Song, arr.items, {}, struct {
        fn lessThan(ctx: void, lhs: Song, rhs: Song) bool {
            _ = ctx;
            const artist_order = std.ascii.orderIgnoreCase(lhs.artist, rhs.artist);
            if (artist_order == .eq) {
                const title_order = std.ascii.orderIgnoreCase(lhs.title, rhs.title);
                return title_order == .lt;
            } else {
                return artist_order == .lt;
            }
        }
    }.lessThan);

    return arr.toOwnedSlice();
}

pub fn resolvePaths(self: *Self, allocator: std.mem.Allocator, path_prefix: []const u8) !void {
    if (!std.fs.path.isAbsolute(self.album_art)) {
        const old_path = self.album_art;
        self.album_art = try std.fs.path.join(allocator, &.{ path_prefix, self.album_art });
        allocator.free(old_path);
    }
    if (!std.fs.path.isAbsolute(self.video)) {
        const old_path = self.video;
        self.video = try std.fs.path.join(allocator, &.{ path_prefix, self.video });
        allocator.free(old_path);
    }
}

pub fn free(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.title);
    allocator.free(self.artist);
    allocator.free(self.album_art);
    allocator.free(self.video);
}