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
layout (location = 3) in vec2 aTexcoord;

uniform mat4 m_Model;

out vec4 position;


void main() {
    mat4 mvp = Camera.m_Project * Camera.m_View * m_Model;
    vec4 position4 = vec4(aPosition, 1.0);
    position = position4;
    gl_Position = mvp * vec4(aPosition, 1.0);
}