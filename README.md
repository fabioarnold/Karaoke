# Karaoke Player

Provides a menu for playing Karaoke videos. Audio input from a microphone is automatically mixed with output from videos. Videos can be paused and scrubbed.

![Screenshot](/screenshot.png?raw=true "Screenshot")

## Requirements

* Zig compiler (https://ziglang.org - tested on 0.9.0-dev.663+c234d4790)
* SDL2 (https://libsdl.org)
* FFmpeg (https://ffmpeg.org)

On Windows [vcpkg](https://github.com/microsoft/vcpkg) is used.

## Installation

```bash
$ git clone https://github.com/fabioarnold/Karaoke.git
$ cd Karaoke
$ zig build run
```

## Setup

Due to copyright reasons no actual content is provided with the software. Individual songs must be stored in json files with associated files for an album cover art and the actual Karaoke video.

Example for `seagulls.json`:
```json
{
    "title": "Seagulls! (Stop It Now)",
    "artist": "Bad Lip Reading",
    "album_art": "art/seagulls.jpg",
    "video": "video/seagulls.mp4"
}
```

The player non-recursively searches the `songs` directory located next to the executable as well as `$USERPREFDIR/FabioWare/Karaoke/songs` (`%APPDATA%` on Windows). Paths within song files can be specified absolute or relative to the file itself. Songs are sorted by artist and song title.

There's a `settings.json` file after the first run in `$USERPREFDIR/FabioWare/Karaoke` which allows among other things disabling microphone input and adjustung the output volume.

## Controls

* Left/right: select a song in the menu or scrub the song while paused or playing
* Enter: start song, resume playing when paused
* Escape: exit application from the menu, pause song, exit current song when paused
* F11: toggle fullscreen

## Credits

* Icon by Nando Design Studio (Fernando Albuquerque)
* Background video by videvo: https://www.videvo.net/video/disco-lights-background-loop-2/1684/
* NanoVG by Mikko Mononen https://github.com/memononen/nanovg
* zalgebra by Alexandre Chêne https://github.com/kooparse/zalgebra
* zgl by Felix Queißner https://github.com/ziglibs/zgl

## License

This software is licensed under MIT License, see [LICENSE](https://github.com/fabioarnold/Karaoke/blob/master/LICENSE) for more information.