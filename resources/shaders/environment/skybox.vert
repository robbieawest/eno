#version 440
layout(location = 0) in vec3 aPos;

out vec3 texCoords;

uniform mat4 m_Projection;
uniform mat4 m_View;

void main() {
    texCoords = aPos;
    vec4 position = m_Projection * m_View * vec4(aPos, 1.0);
    gl_Position = position.xyww;
}