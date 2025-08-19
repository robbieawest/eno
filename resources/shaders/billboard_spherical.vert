#version 440

layout (std140, binding = 0) uniform CameraInfo {
    vec3 position;
    float _pad;
    mat4 m_View;
    mat4 m_Project;
} Camera;

// Expects simple quad

layout(location = 0) in vec3 aPosition;

uniform mat4 m_Model;
uniform mat4 m_Normal;
out vec2 texCoords;
out mat3 TBN;
out vec3 position;
out vec3 cameraPosition;
out vec3 geomNormal;

mat4 billboardModel(mat4 model) {
    vec3 scale = vec3(length(vec3(model[0])), length(vec3(model[1])), length(vec3(model[2])));
    model[0] = vec3(scale.x, 0.0, 0.0);
    model[1] = vec3(0.0, scale.y, 0.0);
    model[2] = vec3(0.0, 0.0, scale.z);
    return model;
}

void main() {
    texCoords = (aPosition + 1.0) * 0.5;
    vec3 normal = vec3(0.0, -1.0, 0.0);
    vec3 tangent = vec3(1.0, 0.0, 0.0);

    // /\ Tangent space
    // \/ World space

    normal = normalize(m_Normal * normal);
    tangent = normalize(m_Normal * tangent);

    TBN = mat3(tangent, cross(normal, tangent), normal);
    position = m_Model * vec4(aPosition, 1.0);
    gl_Position = Camera.m_Project * Camera.m_View * position;

    // \/ Tangent space
    position = TBN * position;
    cameraPosition = TBN * Camera.position;
    geomNormal = TBN * normal;
}