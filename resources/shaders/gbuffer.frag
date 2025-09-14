#version 440

#ifdef NORMAL_INPUT
in vec3 normal;
out vec3 outNormal;
#endif
#ifdef POSITION_INPUT
in vec3 position;
out vec3 outPosition;
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
    outNormal = normal;
    #endif
    #ifdef POSITION_INPUT
    outPosition = position;
    #endif
}