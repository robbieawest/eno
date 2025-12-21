#version 440

#include "pbr/material.glsl"
#include "pbr/geom_util.glsl"

// IO is view space

#ifdef NORMAL_INPUT
in vec3 normal;
layout(location = 0) out vec4 outNormal;
#endif

#ifdef POSITION_INPUT
in vec3 position;
layout(location = 1) out vec4 outPosition;
#endif

#ifdef TANGENT_INPUT
layout(location = 3) in TangentNormalSign tangentNormalSign;
#endif

#ifdef TEXCOORD_INPUT
layout(location = 2) in vec2 texCoords;
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
    vec3 vNormal;  // View space
    if (materialIsUsed(NormalTexture)) {
        vec3 texNormal = texture(normalTexture, texCoords).rgb * 2.0 - 1.0;  // Tangent space
        vNormal = orthogonalize(tangentNormalSign) * texNormal;
    }
    else {
        vNormal = normal;
    }

    vNormal = (vNormal + 1.0) * 0.5;
    outNormal = vec4(normalize(gl_FrontFacing ? vNormal: -vNormal), 1.0);
    #endif

    #ifdef POSITION_INPUT
    outPosition = vec4(position, 1.0);
    #endif
}