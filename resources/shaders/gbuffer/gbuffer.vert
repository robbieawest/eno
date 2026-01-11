#version 440

#include "pbr/material.glsl"
#include "pbr/geom_util.glsl"

layout (std140, binding = 0) uniform CameraInfo {
    vec3 position;
    float _pad;
    mat4 m_View;
    mat4 m_Project;
} Camera;

uniform mat4 m_Model;
mat3 normalMatrix = transpose(inverse(mat3(Camera.m_View * m_Model)));

#ifdef NORMAL_INPUT
layout(location = 0) in vec3 aNormal;
out vec3 normal;
#endif

vec3 geometryNormal() {
    return normalMatrix * aNormal;
}

#ifdef POSITION_INPUT
layout(location = 1) in vec3 aPosition;
out vec3 position;
#endif

#ifdef TANGENT_INPUT
layout(location = 2) in vec4 aTangent;
layout(location = 3) out TangentNormalSign tangentNormalSign;
#endif

#ifdef TEXCOORD_INPUT
#ifdef TANGENT_INPUT
layout(location = 3) in vec2 aTexCoord;
#else
layout(location = 2) in vec2 aTexCoord;
#endif

layout(location = 2) out vec2 texCoords;

#endif


void main() {
    #ifdef POSITION_INPUT
    vec4 viewPos = Camera.m_View * m_Model * vec4(aPosition, 1.0);
    gl_Position = Camera.m_Project * viewPos;
    position = viewPos.xyz;
    #endif

    #ifdef NORMAL_INPUT
    normal = geometryNormal();

    #ifdef TANGENT_INPUT
    tangentNormalSign = getTangentNormalSign(normalMatrix, normal, aTangent);
    #endif

    #endif

    #ifdef TEXCOORD_INPUT
    texCoords = aTexCoord;
    #endif
}
