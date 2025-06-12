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
        // Calculate normalized position within the shape
        vec2 normalizedPos = (pixelPos - center) / halfSize;
        float absX = abs(normalizedPos.x);
        float absY = abs(normalizedPos.y);
        
        // Calculate the angle from center for smooth transitions
        float angle = atan(pixelPos.y - center.y, pixelPos.x - center.x);
        
        // Determine if we're in a corner region based on the rounded box shape
        vec2 cornerCheckPos = abs(pixelPos - center) - (halfSize - vec2(borderRadius));
        bool inCorner = cornerCheckPos.x > 0.0 && cornerCheckPos.y > 0.0;
        
        // Calculate distance from outer edge for gradient
        float distFromOuter = -outerDist;
        float gradientPos = clamp(distFromOuter / borderWidth, 0.0, 1.0);
        
        vec4 borderColor = backgroundColor;
        
        // Calculate influence of each edge based on distance
        float leftInfluence = 1.0 - smoothstep(0.0, borderRadius * 2.0, pixelPos.x);
        float rightInfluence = 1.0 - smoothstep(0.0, borderRadius * 2.0, itemSize.x - pixelPos.x);
        float topInfluence = 1.0 - smoothstep(0.0, borderRadius * 2.0, pixelPos.y);
        float bottomInfluence = 1.0 - smoothstep(0.0, borderRadius * 2.0, itemSize.y - pixelPos.y);
        
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