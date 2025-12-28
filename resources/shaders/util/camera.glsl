
layout (std140, binding = 0) uniform CameraInfo {
    vec3 position;
    float _pad;
    mat4 m_View;
    mat4 m_Project;
    mat4 m_InvProject;
    float zNear;
    float zFar;
} Camera;
