#version 440

#include "pbr/geom_util.glsl"
#include "util/camera.glsl"

layout (location = 0) in vec3 aNormal;
layout (location = 1) in vec3 aPosition;

#ifdef CONTAINS_TANGENT
layout (location = 2) in vec4 aTangent;
layout (location = 3) in vec2 aTexCoords;
#else
layout (location = 2) in vec2 aTexCoords;
#endif

uniform mat4 m_Model;
uniform mat3 m_Normal;

out vec3 position;
out vec3 geomNormal;
out vec2 texCoords;
out vec3 cameraPosition;
out mat3 transView;

#ifdef CONTAINS_TANGENT
out mat3 TBN;
#endif

void main() {
    texCoords = aTexCoords;

    position = vec3(m_Model * vec4(aPosition, 1.0));
    gl_Position = Camera.m_Project * Camera.m_View * vec4(position, 1.0);

    geomNormal = normalize(m_Normal * aNormal);

    #ifdef CONTAINS_TANGENT
    TBN = getTBN(m_Normal, geomNormal, aTangent);
    #endif

    // Apply TBN to outgoing values
    // position = TBN * position;
    // cameraPosition = TBN * Camera.position;
    // geomNormal = TBN * geomNormal;
    cameraPosition = Camera.position;
    transView = transpose(mat3(Camera.m_View));

    // TBN will be used to translate light positions to tangent space in fragment shader
    // - this is biting the bullet, sending a fixed buffer of tangent light positions from vertex -> fragment is more complex and the performance benefit is
    // dubious
}