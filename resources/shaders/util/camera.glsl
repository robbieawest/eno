
layout (std140, binding = 0) uniform CameraInfo {
    vec3 position;
    float _pad;
    mat4 m_View;
    mat4 m_Project;
    mat4 m_InvProject;
    float zNear;
    float zFar;
    vec2 _pad2;
} Camera;

float linearizeDepth(float projDepth) {
    float zNear = Camera.zNear;
    float zFar = Camera.zFar;
    return 2.0 * zNear * zFar / (zFar + zNear - (2.0 * projDepth - 1.0) * (zFar - zNear));
}
