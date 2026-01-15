// -----------------------------------------------------------------------
// 输入参数 (Custom Node Inputs):
// 1. InColor (float3): 
//    连接 [SceneTexture:PostProcessInput0] (Color)。
//
// 2. Steps (float): 
//    色阶层数，建议 4.0 - 8.0。数值越小，色块越明显（概括性越强）；数值越大越接近原图。
//
// 3. Softness (float): 
//    过渡柔和度，建议 0.1 - 0.3。
//    0.0 = 硬切边（类似赛璐珞/硬漫）。
//    0.5+ = 极度柔和（类似水彩晕染）。
//
// 4. OutlineStrength (float): 
//    轮廓线强度，建议 0.5。基于色彩差异自动描边。
// -----------------------------------------------------------------------
float3 src = InColor;

// 1. 频率分析 (Frequency Analysis)
// -----------------------------------------------------------------------
// [目标] 区分平滑/中频噪点/硬边，让高频噪点在中间段被概括，硬边被保护

float luma = dot(src, float3(0.299, 0.587, 0.114));
float freq = fwidth(luma);
float isMidFreq = smoothstep(0.05, 0.15, freq) * (1.0 - smoothstep(0.28, 0.45, freq));

// 2x2 模拟均值模糊，仅作用于中频区
float3 blurredSrc = src + (ddx(src) + ddy(src)) * 0.35;
float3 processSrc = lerp(src, blurredSrc, isMidFreq);
float processLuma = dot(processSrc, float3(0.299, 0.587, 0.114));

// 2. 自适应量化 (Adaptive Quantization)
// -----------------------------------------------------------------------
float targetSteps = max(2.0, Steps);
float activeSteps = lerp(targetSteps, 2.0, isMidFreq);
float activeSnap = lerp(5.0, 60.0, isMidFreq);

float val = processLuma * activeSteps;
float dist = frac(val) - 0.5;
float snapped = sign(dist) * smoothstep(0.0, 1.0, abs(dist) * 2.0 + (activeSnap * dist * dist));
float quantizedLuma = (floor(val) + 0.5 + snapped * 0.5) / activeSteps;
quantizedLuma = quantizedLuma * 0.9 + 0.1;

// 3. 重建与保护
float safeLuma = max(processLuma, 0.001);
float3 finalColor = processSrc * (quantizedLuma / safeLuma);

if (isMidFreq > 0.3)
{
    float3 gray = finalColor * 0.7;
    finalColor = lerp(finalColor, gray, 0.4);
    float3 superBlur = finalColor + (ddx(finalColor) + ddy(finalColor)) * 0.3;
    finalColor = lerp(finalColor, superBlur, 0.5);
}

// 4. 轮廓线 (Outline)
if (OutlineStrength > 0.01)
{
    float edgeMask = smoothstep(0.35, 0.65, freq);
    finalColor = lerp(finalColor, finalColor * (1.0 - OutlineStrength * 0.6), edgeMask);
}

return finalColor;