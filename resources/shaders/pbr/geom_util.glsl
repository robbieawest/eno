

vec3 orthogonalize(vec3 from, vec3 to) {
    return normalize(from - dot(from, to) * to);
}

// todo remove?
mat3 getTBN(mat3 normalMatrix, vec3 normal, vec4 tangent) {
    float bitangentSign = tangent.w;
    vec3 T = normalize(normalMatrix* vec3(tangent));
    // vec3 tangent = normalize(cross(normal, vec3(0.0, 1.0, 1.0)));  // approximation

    // Orthogonalize tangent to normal
    T = orthogonalize(T, normal);
    vec3 bitangent = cross(normal, T) * bitangentSign;
    return mat3(T, bitangent, normal);
}

struct TangentNormalSign {
    vec3 tangent;
    vec3 normal;
    float sign;
};

TangentNormalSign getTangentNormalSign(mat3 normalMatrix, vec3 viewNormal, vec4 tangent) {
    vec3 T = normalize(normalMatrix * vec3(tangent));

    // Orthogonalize tangent to normal
    T = orthogonalize(T, viewNormal);

    TangentNormalSign ret;
    ret.normal = viewNormal;
    ret.tangent = T;
    ret.sign = tangent.w;

    return ret;
}

// To be used on an interpolated TangentNormalSign
mat3 orthogonalize(TangentNormalSign tangentNormalSign) {
    vec3 normal = tangentNormalSign.normal;
    vec3 tangent = orthogonalize(tangentNormalSign.tangent, normal);
    vec3 bitangent = cross(normal, tangent) * tangentNormalSign.sign;
    return mat3(tangent, bitangent, normal);
}

#ifdef INCLUDE_FRAG_UTILS

mat3 calculateTBN(vec3 position, vec2 texCoords, vec3 geomNormal) {
    vec3 Q1  = dFdx(position);
    vec3 Q2  = dFdy(position);
    vec2 st1 = dFdx(texCoords);
    vec2 st2 = dFdy(texCoords);

    vec3 gNormal = normalize(geomNormal);
    vec3 tangent = normalize(Q1 * st2.t - Q2 * st1.t);
    vec3 bitangent = -normalize(cross(gNormal, tangent));
    return mat3(tangent, bitangent, gNormal);
}

#endif
