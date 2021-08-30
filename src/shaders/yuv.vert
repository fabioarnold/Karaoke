uniform mat4 mvp;

attribute vec3 position;

varying vec2 v_texcoords;

void main() {
    v_texcoords = vec2(0.5, -0.5) * position.xy + vec2(0.5);
    gl_Position = mvp * vec4(position, 1);
}