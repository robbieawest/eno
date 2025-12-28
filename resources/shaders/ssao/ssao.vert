#version 440

#include "util/camera.glsl"

layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec2 aTexCoords;

out vec2 texCoords;
out mat4 m_Project;
// out mat4 m_ProjectInv;
out vec3 viewRay;

void main() {
    texCoords = aTexCoords;
    gl_Position = vec4(aPosition, 1.0);
    m_Project = Camera.m_Project;

    // View ray construction (interpolated to frag)
    vec4 clipPos = vec4(aPosition.xy, 1.0, 1.0);
    vec4 viewPos = Camera.m_InvProject * clipPos;
    viewPos /= viewPos.w;
    viewRay = viewPos.xyz / -viewPos.z;
}