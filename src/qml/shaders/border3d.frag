#version 440

layout(location = 0) in vec2 coord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float borderWidth;
    float borderRadius;
    vec4 backgroundColor;
    vec4 lightColor;
    vec4 shadowColor;
    float lightIntensity;
    float shadowIntensity;
    float lightAngle;
};

float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + r;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

float smootherstep(float edge0, float edge1, float x) {
    x = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
}

void main() {
    vec2 pixelPos = coord * itemSize;
    vec2 center = itemSize * 0.5;
    vec2 halfSize = itemSize * 0.5;
    
    // Calculate distances to edges
    float outerDist = sdRoundedBox(pixelPos - center, halfSize, borderRadius);
    float innerDist = sdRoundedBox(pixelPos - center, halfSize - vec2(borderWidth), max(0.0, borderRadius - borderWidth));
    
    // Anti-aliasing
    float aa = 1.5;
    float outerAlpha = 1.0 - smoothstep(-aa, 0.0, outerDist);
    
    // Check if we're in the border area
    bool inBorder = outerDist <= 0.0 && innerDist > 0.0;
    
    vec4 finalColor = backgroundColor;
    
    if (inBorder) {
        // Calculate position relative to nearest edge
        vec2 absPos = abs(pixelPos - center);
        vec2 edgeDistances = halfSize - absPos;
        
        // Determine which edge we're on
        float leftDist = pixelPos.x - borderWidth;
        float rightDist = itemSize.x - pixelPos.x - borderWidth;
        float topDist = pixelPos.y - borderWidth;
        float bottomDist = itemSize.y - pixelPos.y - borderWidth;
        
        // Calculate minimum distance to inner edge
        float minInnerDist = min(min(leftDist, rightDist), min(topDist, bottomDist));
        
        // Calculate border gradient position (0 at outer edge, 1 at inner edge)
        float borderPos = clamp(minInnerDist / borderWidth, 0.0, 1.0);
        
        // Determine primary edge for lighting
        vec4 borderColor = backgroundColor;
        
        // Check which edge we're closest to
        if (edgeDistances.y < borderRadius && edgeDistances.x < borderRadius) {
            // Corner region - blend based on angle
            vec2 cornerPos = pixelPos - center;
            float angle = atan(cornerPos.y, cornerPos.x);
            
            // Light from top-left (-135 degrees)
            float lightAngle = -135.0 * 3.14159 / 180.0;
            float dotLight = cos(angle - lightAngle);
            
            // Smooth blend between light and shadow
            float lightBlend = smoothstep(-0.7, 0.7, dotLight);
            borderColor = mix(
                mix(backgroundColor, shadowColor, shadowIntensity),
                mix(backgroundColor, lightColor, lightIntensity),
                lightBlend
            );
        } else {
            // Straight edge regions
            if (pixelPos.y < borderWidth) {
                // Top edge - light
                borderColor = mix(backgroundColor, lightColor, lightIntensity);
            } else if (pixelPos.y > itemSize.y - borderWidth) {
                // Bottom edge - shadow
                borderColor = mix(backgroundColor, shadowColor, shadowIntensity);
            } else if (pixelPos.x < borderWidth) {
                // Left edge - light
                borderColor = mix(backgroundColor, lightColor, lightIntensity);
            } else if (pixelPos.x > itemSize.x - borderWidth) {
                // Right edge - shadow
                borderColor = mix(backgroundColor, shadowColor, shadowIntensity);
            }
        }
        
        // Apply gradient from outer to inner edge
        finalColor = mix(borderColor, backgroundColor, borderPos * borderPos);
    }
    
    // Apply alpha
    finalColor.a *= outerAlpha;
    
    fragColor = finalColor * qt_Opacity;
}