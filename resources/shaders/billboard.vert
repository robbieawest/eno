#version 440

layout (std140, binding = 0) uniform CameraInfo {
    vec3 position;
    float _pad;
    mat4 m_View;
    mat4 m_Project;
} Camera;


layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec2 aTexCoords;

uniform mat4 m_Model;
out vec2 texCoords;

void main() {
    texCoords = aTexCoords;
    gl_Position = Camera.m_Project * Camera.m_View * m_Model * vec4(aPosition, 1.0);
}