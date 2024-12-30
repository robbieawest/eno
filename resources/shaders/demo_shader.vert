#version 440

layout (location = 0) in vec3 aNormal;
layout (location = 1) in vec3 aPosition;
layout (location = 2) in vec4 aTangent;
layout (location = 3) in vec2 aTexcoord;


void main() {
    gl_Position = vec4(aPosition, 1.0);
}