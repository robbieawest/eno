#version 440

#ifdef NORMAL_INPUT
smooth in vec3 normal;
out vec4 outNormal;
#endif
#ifdef POSITION_INPUT
in vec3 position;
out vec4 outPosition;
#endif

/* Unused
#ifdef TEXCOORD_INPUT
in vec3 aTexCoord;
#endif
#ifdef TANGENT_INPUT
in vec3 aTangent;
#endif
*/

void main() {
    #ifdef NORMAL_INPUT
    outNormal = vec4(normal, 1.0);
    #endif
    #ifdef POSITION_INPUT
    outPosition = vec4(position, 1.0);
    #endif
}