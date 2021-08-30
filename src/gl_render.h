#include <SDL2/SDL.h>

// replacements for SDL2 render functions used by ffplay

typedef struct GL_Texture GL_Texture;

GL_Texture *GL_CreateTexture(Uint32 format, int access, int w, int h);
void GL_DestroyTexture(GL_Texture *texture);
int GL_QueryTexture(GL_Texture *texture, unsigned int *format, int *access, int *w, int *h);
void GL_UpdateTextureYUV(GL_Texture *texture,
                         const Uint8 *Yplane, int Ypitch,
                         const Uint8 *Uplane, int Upitch,
                         const Uint8 *Vplane, int Vpitch);
void GL_BindTextureYUV(GL_Texture *texture);
void GL_DrawTextureEx(GL_Texture *texture, const SDL_Rect *rect, const SDL_RendererFlip flip);