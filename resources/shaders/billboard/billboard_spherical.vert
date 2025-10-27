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
out vec2 texCoords;
out mat3 TBN;
out mat3 transView;
out vec3 position;
out vec3 cameraPosition;
out vec3 geomNormal;

mat4 billboardModelView(mat4 modelView) {
    vec3 scale = vec3(length(vec3(modelView[0])), length(vec3(modelView[1])), length(vec3(modelView[2])));
    modelView[0] = vec4(scale.x, 0.0, 0.0, 0.0);
    modelView[1] = vec4(0.0, scale.y, 0.0, 0.0);
    modelView[2] = vec4(0.0, 0.0, scale.z, 0.0);
    return modelView;
}

void main() {
    texCoords = vec2 (aPosition + 1.0) * 0.5;

    geomNormal = vec3(0.0, -1.0, 0.0);
    vec3 tangent = vec3(1.0, 0.0, 0.0);
    // /\ Tangent space

    mat4 modelView = billboardModelView(Camera.m_View * m_Model);
    position = vec3(modelView * vec4(aPosition, 1.0));  // Model View space
    gl_Position = Camera.m_Project * vec4(position, 1.0);

    mat3 modelView3 = mat3(modelView);
    mat3 invView3 = mat3(inverse(Camera.m_View));

    // \/ World space
    vec3 normal = normalize(invView3 * modelView3 * geomNormal);
    tangent = normalize(invView3 * modelView3 * tangent);

    TBN = mat3(tangent, cross(normal, tangent), normal);

    // \/ Tangent space
    position = TBN * position;
    cameraPosition = TBN * Camera.position;

    transView = transpose(mat3(Camera.m_View));
}