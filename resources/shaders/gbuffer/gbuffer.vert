#version 440

layout (std140, binding = 0) uniform CameraInfo {
    vec3 position;
    float _pad;
    mat4 m_View;
    mat4 m_Project;
} Camera;

#ifdef NORMAL_INPUT
layout(location = 0) in vec3 aNormal;
smooth out vec3 normal;

#ifdef POSITION_INPUT
layout(location = 1) in vec3 aPosition;
out vec3 position;
#endif

#elif defined(POSITION_INPUT)
layout(location = 0) in vec3 aPosition;
out vec3 position;
#endif

/* Unused
#ifdef TEXCOORD_INPUT
in vec3 aTexCoord;
#endif
#ifdef TANGENT_INPUT
in vec3 aTangent;
#endif
*/

uniform mat4 m_Model;

void main() {
    #ifdef POSITION_INPUT
    vec4 viewPos = Camera.m_View * m_Model * vec4(aPosition, 1.0);
    gl_Position = Camera.m_Project * viewPos;
    position = viewPos.xyz;
    #endif
    #ifdef NORMAL_INPUT
    mat3 normalMatrix = transpose(inverse(mat3(Camera.m_View * m_Model)));
    normal = normalMatrix * aNormal;
    #endif
}
