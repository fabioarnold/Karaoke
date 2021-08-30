#include <SDL2/SDL.h>

typedef struct VideoState VideoState;
typedef struct VideoContext VideoContext;

VideoContext *video_init(int freq, int channels, unsigned audio_buffer_size);
void video_quit(VideoContext *vc);

VideoState *stream_open(const char *filename, VideoContext *vc);
void stream_close(VideoState *is);

void video_get_dims(VideoState *is, int *width, int *height);
// get duration in seconds
double video_get_duration(VideoState *is);
// get current position in seconds
double video_get_position(VideoState *is);
int video_is_paused(VideoState *is);
int video_is_finished(VideoState *is);

void video_set_paused(VideoState *is, int pause);
void video_set_looping(VideoState *is, int loop);
void video_set_volume(VideoState *is, float volume);
// seeks to the timestamp in microseconds
void video_stream_seek(VideoState *is, int64_t timestamp_us);

// updates texture
void video_update(VideoState *is);
void video_bind_texture(VideoState *is);

void video_sdl_audio_callback(VideoState *video, Uint8 *stream, int len);
