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
out vec3 geomNormal;
out vec2 texCoords;
out vec3 cameraPosition;
out mat3 TBN;

void main() {
    texCoords = aTexCoords;

    position = vec3(m_Model * vec4(aPosition, 1.0));
    gl_Position = Camera.m_Project * Camera.m_View * vec4(position, 1.0);

    geomNormal = normalize(m_Normal * aNormal);

    float bitangentSign = aTangent.w;
    vec3 tangent = normalize(m_Normal * vec3(aTangent));
    // vec3 tangent = normalize(cross(normal, vec3(0.0, 1.0, 1.0)));  // approximation

    // Orthogonalize tangent to normal
    tangent = normalize(tangent - dot(tangent, geomNormal) * geomNormal);
    vec3 bitangent = cross(geomNormal, tangent) * bitangentSign;
    TBN = transpose(mat3(tangent, bitangent, geomNormal));

    // Apply TBN to outgoing values
    position = TBN * position;
    cameraPosition = TBN * Camera.position;
    geomNormal = TBN * geomNormal;

    // TBN will be used to translate light positions to tangent space in fragment shader
    // - this is biting the bullet, sending a fixed buffer of tangent light positions from vertex -> fragment is more complex and the performance benefit is
    // dubious
}