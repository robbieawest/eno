#version 440
layout (location = 0) in vec3 aPos;

out vec3 position;

uniform mat4 m_Project;
uniform mat4 m_View;

void main() {
    position = aPos;
    gl_Position = m_Project * m_View * vec4(position, 1.0);
}