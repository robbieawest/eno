#version 440

layout (std140, binding = 0) uniform CameraInfo {
    vec3 position;
    float _pad;
    mat4 m_View;
    mat4 m_Project;
} Camera;

layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec2 aTexCoords;

out vec2 texCoords;
out mat4 m_Project;
out mat4 m_ProjectInv;

void main() {
    texCoords = aTexCoords;
    gl_Position = vec4(aPosition, 1.0);
    m_Project = Camera.m_Project;
    m_ProjectInv = inverse(m_Project);
}