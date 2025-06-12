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
    // Adjust halfSize to account for QML's border rendering
    vec2 adjustedHalfSize = halfSize - vec2(0.5);
    float adjustedRadius = borderRadius - 0.5;
    
    float outerDist = sdRoundedBox(pixelPos - center, adjustedHalfSize, adjustedRadius);
    float innerDist = sdRoundedBox(pixelPos - center, adjustedHalfSize - vec2(borderWidth), max(0.0, adjustedRadius - borderWidth));
    
    // Anti-aliasing - use a much smaller value for crisp edges
    float aa = 0.5;
    float outerAlpha = 1.0 - smoothstep(-aa, aa, outerDist);
    
    // Early exit if completely outside the rounded rectangle
    if (outerDist > aa) {
        discard;
    }
    
    // Check if we're in the border area
    bool inBorder = outerDist <= 0.0 && innerDist > 0.0;
    
    vec4 finalColor = backgroundColor;
    
    if (inBorder) {
        // Calculate position relative to the shape
        vec2 absPos = abs(pixelPos - center);
        
        // Check if we're in a corner region
        vec2 cornerOffset = absPos - (adjustedHalfSize - vec2(adjustedRadius));
        bool inCorner = cornerOffset.x > 0.0 && cornerOffset.y > 0.0;
        
        // Calculate distance from outer edge for gradient
        float distFromOuter = -outerDist;
        float gradientPos = clamp(distFromOuter / borderWidth, 0.0, 1.0);
        
        vec4 borderColor = backgroundColor;
        
        // Calculate influence of each edge based on distance
        // Use smaller falloff distance for sharper transitions
        float falloffDist = adjustedRadius * 1.5;
        float leftInfluence = 1.0 - smoothstep(0.0, falloffDist, pixelPos.x);
        float rightInfluence = 1.0 - smoothstep(0.0, falloffDist, itemSize.x - pixelPos.x);
        float topInfluence = 1.0 - smoothstep(0.0, falloffDist, pixelPos.y);
        float bottomInfluence = 1.0 - smoothstep(0.0, falloffDist, itemSize.y - pixelPos.y);
        
        // For corners, adjust influences based on actual position within the rounded shape
        if (inCorner) {
            float cornerDist = length(cornerOffset);
            float cornerFactor = 1.0 - smoothstep(0.0, adjustedRadius, cornerDist);
            
            // Determine which corner we're in and adjust influences
            if (pixelPos.x > center.x && pixelPos.y < center.y) {
                // Top-right
                rightInfluence *= cornerFactor;
                topInfluence *= cornerFactor;
            } else if (pixelPos.x < center.x && pixelPos.y < center.y) {
                // Top-left
                leftInfluence *= cornerFactor;
                topInfluence *= cornerFactor;
            } else if (pixelPos.x < center.x && pixelPos.y > center.y) {
                // Bottom-left
                leftInfluence *= cornerFactor;
                bottomInfluence *= cornerFactor;
            } else {
                // Bottom-right
                rightInfluence *= cornerFactor;
                bottomInfluence *= cornerFactor;
            }
        }
        
        // Normalize influences
        float totalInfluence = leftInfluence + rightInfluence + topInfluence + bottomInfluence;
        if (totalInfluence > 0.0) {
            leftInfluence /= totalInfluence;
            rightInfluence /= totalInfluence;
            topInfluence /= totalInfluence;
            bottomInfluence /= totalInfluence;
        }
        
        // Calculate color contributions from each edge
        vec4 leftContribution = mix(backgroundColor, lightColor, lightIntensity * leftInfluence);
        vec4 rightContribution = mix(backgroundColor, shadowColor, shadowIntensity * rightInfluence);
        vec4 topContribution = mix(backgroundColor, lightColor, lightIntensity * topInfluence);
        vec4 bottomContribution = mix(backgroundColor, shadowColor, shadowIntensity * bottomInfluence);
        
        // Blend all contributions
        borderColor = backgroundColor;
        borderColor = mix(borderColor, leftContribution, leftInfluence);
        borderColor = mix(borderColor, rightContribution, rightInfluence);
        borderColor = mix(borderColor, topContribution, topInfluence);
        borderColor = mix(borderColor, bottomContribution, bottomInfluence);
        
        // Apply smooth gradient from outer to inner edge
        float gradientCurve = 1.0 - pow(gradientPos, 2.2);
        finalColor = mix(backgroundColor, borderColor, gradientCurve);
    }
    
    // Apply alpha
    finalColor.a *= outerAlpha;
    
    fragColor = finalColor * qt_Opacity;
}