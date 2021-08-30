#include <SDL2/SDL.h>

#include "glad/glad.h"

typedef struct GL_Texture
{
    int w;
    int h;
    //GLint internal_format;
    GLenum format;
    GLenum formattype;
    GLuint texture;
    GLuint utexture;
    GLuint vtexture;

    Uint32 sdl_format;
    int sdl_access;
} GL_Texture;

void GL_CreateTextureYUV(GL_Texture *data, int width, int height);

GL_Texture *GL_CreateTexture(Uint32 format, int access, int width, int height)
{
    if (format != SDL_PIXELFORMAT_IYUV)
        return NULL; // unsupported
    GL_Texture *texture = malloc(sizeof(GL_Texture));
    texture->sdl_format = format;
    texture->sdl_access = access;
    GL_CreateTextureYUV(texture, width, height);
    return texture;
}

void GL_DestroyTexture(GL_Texture *texture)
{
    glDeleteTextures(1, &texture->texture);
    glDeleteTextures(1, &texture->utexture);
    glDeleteTextures(1, &texture->vtexture);
    free(texture);
}

int GL_QueryTexture(GL_Texture *texture, Uint32 *sdl_format, int *sdl_access, int *w, int *h)
{
    if (sdl_format)
        *sdl_format = texture->sdl_format;
    if (sdl_access)
        *sdl_access = texture->sdl_access;
    if (w)
        *w = texture->w;
    if (h)
        *h = texture->h;
    return 0;
}

void GL_CreateTextureYUV(GL_Texture *data, int width, int height)
{
    data->w = width;
    data->h = height;
    GLint internal_format = GL_LUMINANCE;
    data->format = GL_LUMINANCE;
    data->formattype = GL_UNSIGNED_BYTE;

    int bytes_per_pixel = 1; // yuv
    int pitch = width * bytes_per_pixel;

    int size = height * pitch;
    // add size of u and v plane
    size += 2 * ((height + 1) / 2) * ((pitch + 1) / 2);

    GLenum scale_mode = GL_LINEAR;

    glGenTextures(1, &data->texture);
    glBindTexture(GL_TEXTURE_2D, data->texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, scale_mode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, scale_mode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, internal_format, width, height, 0, data->format, data->formattype, NULL);

    glGenTextures(1, &data->utexture);
    glGenTextures(1, &data->vtexture);

    glBindTexture(GL_TEXTURE_2D, data->utexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, scale_mode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, scale_mode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, internal_format, (width + 1) / 2, (height + 1) / 2, 0, data->format, data->formattype, NULL);

    glBindTexture(GL_TEXTURE_2D, data->vtexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, scale_mode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, scale_mode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, internal_format, (width + 1) / 2, (height + 1) / 2, 0, data->format, data->formattype, NULL);
}

void GL_UpdateTextureYUV(GL_Texture *data,
                         const Uint8 *Yplane, int Ypitch,
                         const Uint8 *Uplane, int Upitch,
                         const Uint8 *Vplane, int Vpitch)
{
    glBindTexture(GL_TEXTURE_2D, data->texture);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, Ypitch);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, data->w,
                    data->h, data->format, data->formattype, Yplane);

    glPixelStorei(GL_UNPACK_ROW_LENGTH, Upitch);
    glBindTexture(GL_TEXTURE_2D, data->utexture);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0 / 2, 0 / 2,
                    (data->w + 1) / 2, (data->h + 1) / 2,
                    data->format, data->formattype, Uplane);

    glPixelStorei(GL_UNPACK_ROW_LENGTH, Vpitch);
    glBindTexture(GL_TEXTURE_2D, data->vtexture);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0 / 2, 0 / 2,
                    (data->w + 1) / 2, (data->h + 1) / 2,
                    data->format, data->formattype, Vplane);
}

void GL_BindTextureYUV(GL_Texture *data)
{
    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, data->vtexture);

    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, data->utexture);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, data->texture);
}

// default: SDL_YUV_CONVERSION_BT709

void GL_Init() {

}

void GL_DrawTextureEx(GL_Texture *texture, const SDL_Rect *rect, const SDL_RendererFlip flip)
{
    // don't use this lol
    GL_BindTextureYUV(texture);
    // TODO: flip
    glRecti(-1,-1,2,2);
}