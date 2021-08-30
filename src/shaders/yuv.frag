uniform sampler2D tex0; // Y
uniform sampler2D tex1; // U
uniform sampler2D tex2; // V    

varying vec2 v_texcoords;

// BT709_SHADER_CONSTANTS
// YUV offset 
const vec3 offset = vec3(-0.0627451017, -0.501960814, -0.501960814);
// RGB coefficients 
const vec3 Rcoeff = vec3(1.1644,  0.000,  1.7927);
const vec3 Gcoeff = vec3(1.1644, -0.2132, -0.5329);
const vec3 Bcoeff = vec3(1.1644,  2.1124,  0.000);

void main() {
    vec2 tcoord;
    vec3 yuv, rgb;

    // Get the Y value 
    tcoord = v_texcoords;
    yuv.x = texture2D(tex0, tcoord).r;

    // Get the U and V values 
    // tcoord *= UVCoordScale;
    yuv.y = texture2D(tex1, tcoord).r;
    yuv.z = texture2D(tex2, tcoord).r;

    // Do the color transform 
    yuv += offset;
    rgb.r = dot(yuv, Rcoeff);
    rgb.g = dot(yuv, Gcoeff);
    rgb.b = dot(yuv, Bcoeff);

    // That was easy. :) 
    gl_FragColor = vec4(rgb, 1.0);
}