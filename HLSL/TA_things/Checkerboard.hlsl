// Checkerboard Pattern HLSL
// Use this code inside a UE5 Material Custom Node
// Inputs: 
//    UV (float2) - Texture coordinates
//    Frequency (float) - Tiling scale (e.g., 8.0)

float2 scaledUV = UV * Frequency;
float2 id = floor(scaledUV);
float checker = frac((id.x + id.y) * 0.5) * 2.0;

return checker;
