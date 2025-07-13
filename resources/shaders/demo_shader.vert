#version 440

layout (std140, binding = 0) uniform CameraInfo {
    vec3 position;
    float _pad;
    mat4 m_View;
    mat4 m_Project;
} Camera;

layout (location = 0) in vec3 aNormal;
layout (location = 1) in vec3 aPosition;
layout (location = 2) in vec4 aTangent;
layout (location = 3) in vec2 aTexCoords;

uniform mat4 m_Model;
uniform mat3 m_Normal;

out vec3 position;
out vec3 normal;
out vec2 texCoords;
out vec3 cameraPosition;

void main() {
    texCoords = aTexCoords;
    position = vec3(m_Model * vec4(aPosition, 1.0));
    normal = m_Normal * aNormal;
    cameraPosition = Camera.position;

    gl_Position = Camera.m_Project * Camera.m_View * vec4(position, 1.0);
}