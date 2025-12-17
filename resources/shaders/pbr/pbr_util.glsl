
#define PI 3.14159265358979323

float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness*roughness;
    float a2 = a*a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float GeomSchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float GeomSmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeomSchlickGGX(NdotV, roughness);
    float ggx1 = GeomSchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

float KelemenVisibility(vec3 L, vec3 H) {
    return 0.25 * pow(max(dot(L, H), 0.0), 2);
}

vec3 FresnelSchlick(vec3 V, vec3 H, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - max(dot(H, V), 0.0), 0.0, 1.0), 5.0);
}

vec3 FresnelSchlickRoughness(vec3 N, vec3 V, vec3 F0, float roughness) {
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - max(dot(N, V), 0.0), 0.0, 1.0), 5.0);
}

vec3 calculateBRDF(vec3 N, vec3 V, vec3 L, vec3 H, vec3 albedo, float roughness, float metallic, vec3 F0, float specular) {
    float NDF = DistributionGGX(N, H, roughness);
    float G = GeomSmith(N, V, L, roughness);
    vec3 fresnel = FresnelSchlick(H, V, F0);

    // Cook-torrence
    vec3 num = NDF * G * fresnel;
    float denom = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specularContrib = specular * (num / denom);

    vec3 diffuseShare = (vec3(1.0) - fresnel) * (1 - metallic);
    vec3 lambertian = albedo / PI;
    return diffuseShare * lambertian + specularContrib;
}

vec3 calculateClearcoatBRDF(vec3 N, vec3 L, vec3 H, float roughness, vec3 Fc) {
    float NDF = DistributionGGX(N, H, roughness);
    float G = KelemenVisibility(L, H);
    return (NDF * G) * Fc;
}

vec3 calculateReflectance(vec3 BRDF, vec3 N, vec3 L, vec3 radiance) {
    return BRDF * radiance * max(dot(N, L), 0.0);
}

vec3 IBLMultiScatterBRDF(vec3 N, vec3 V, vec3 radiance, vec3 irradiance, vec3 albedo, vec2 f_ab, float perceptualRoughness, const bool dielectric, float specular, vec3 specularColour) {
    vec3 F0;
    if (dielectric) F0 = min(vec3(0.04) * specularColour * specular, vec3(1.0));
    else F0 = albedo;

    vec3 kS = FresnelSchlickRoughness(N, V, F0, perceptualRoughness);

    vec3 FssEss = kS * f_ab.x + f_ab.y;
    vec3 specularContrib = FssEss * radiance;

    float Ess = f_ab.x + f_ab.y;
    float Ems = 1 - Ess;
    vec3 Favg = F0 + (1.0 - F0) / 21.0;
    vec3 Fms = FssEss * Favg / (1 - Ems * Favg);
    vec3 FmsEms = Fms * Ems;

    vec3 diffuse = irradiance;
    // Dielectric kD term
    if (dielectric) {  // Full dielectric, metallic = 0
        vec3 Edss = 1.0 - (FssEss + Fms + Ems);
        vec3 kD = albedo * Edss;
        diffuse *= FmsEms + kD;
    }
    else diffuse *= FmsEms;  // Full metal, metallic = 1

    return specularContrib + diffuse;
}