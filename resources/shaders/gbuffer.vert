#version 440

layout (std140, binding = 0) uniform CameraInfo {
    vec3 position;
    float _pad;
    mat4 m_View;
    mat4 m_Project;
} Camera;

#ifdef NORMAL_INPUT
in vec3 aNormal;
smooth out vec3 normal;
#endif
#ifdef POSITION_INPUT
in vec3 aPosition;
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
uniform mat3 m_Normal;

void main() {
    #ifdef POSITION_INPUT
    position = vec3(m_Model * vec4(aPosition, 1.0));
    gl_Position = Camera.m_Project * Camera.m_View * vec4(position, 1.0);
    #endif
    #ifdef NORMAL_INPUT
    normal = normalize(m_Normal * aNormal);
    #endif
}
