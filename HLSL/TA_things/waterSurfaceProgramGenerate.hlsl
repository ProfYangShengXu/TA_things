// 程序化水面生成器 (Water Surface with Physics Interaction)
// Output Type: Float 4
//    XYZ: 法线 (连 Normal)
//    W:   波高 (Height/Displacement)
// 
// ========== 输入参数说明 ==========
// 基础波浪:
//    UV - TextureCoordinate[0]
//    Time - Time 节点
//    WaveScale (5.0) - Scalar Parameter
//    WaveSpeed (0.5) - Scalar Parameter
//    NormalStrength (1.0) - Scalar Parameter
//    WindDirection (float2(1, 0.5)) - Constant2Vector 或 Parameter
//    WaveHeight (0.3) - Scalar Parameter
//
// 物理波纹 (分别连接4个独立参数):
//    RippleCount (0-4) - Scalar Parameter
//    RipplePos0 (float2(-999,-999)) - Vector2 Parameter
//    RipplePos1 (float2(-999,-999)) - Vector2 Parameter  
//    RipplePos2 (float2(-999,-999)) - Vector2 Parameter
//    RipplePos3 (float2(-999,-999)) - Vector2 Parameter
//    RippleTime0 (-999) - Scalar Parameter
//    RippleTime1 (-999) - Scalar Parameter
//    RippleTime2 (-999) - Scalar Parameter
//    RippleTime3 (-999) - Scalar Parameter
//    RippleStrength (1.0) - Scalar Parameter
//
// 视觉效果 (可选):
//    FresnelPower (5.0) - Scalar Parameter
//    RefractionStrength (0.1) - Scalar Parameter

struct WaterTool
{
    // --- 基础哈希函数 ---
    float hash(float2 p)
    {
        return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
    }
    
    float2 hash2(float2 p)
    {
        p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
        return frac(sin(p) * 43758.5453123);
    }

    // --- Gerstner 波算法 ---
    // Gerstner波会产生尖峰和圆滑的谷，更符合真实海浪的形态
    // 参数:
    //   worldPos: 世界空间位置 (使用UV模拟)
    //   direction: 波浪传播方向 (归一化)
    //   wavelength: 波长
    //   amplitude: 振幅
    //   steepness: 陡峭度 (0~1, 越大波峰越尖锐)
    //   speed: 传播速度
    //   time: 时间
    // 返回: float3(offsetX, offsetY, height)
    float3 GerstnerWave(
        float2 worldPos, 
        float2 direction, 
        float wavelength, 
        float amplitude, 
        float steepness,
        float speed,
        float time)
    {
        float k = 2.0 * 3.14159265 / wavelength; // 波数
        float c = sqrt(9.8 / k); // 相速度 (简化重力波公式)
        float2 d = normalize(direction);
        float f = k * (dot(d, worldPos) - c * speed * time);
        float a = steepness / k;
        
        // Gerstner波的核心公式
        float sinF = sin(f);
        float cosF = cos(f);
        
        return float3(
            d.x * a * cosF,  // X方向位移
            d.y * a * cosF,  // Y方向位移
            amplitude * sinF // 高度
        );
    }

    // --- 多层Gerstner波叠加（平缓版：混乱但流畅）---
    float3 GetGerstnerWaves(float2 uv, float time, float scale, float speed, float waveHeight, float2 windDir)
    {
        float2 worldPos = uv * scale;
        float3 totalWave = float3(0, 0, 0);
        
        // 轻微的全局噪声偏移
        float2 globalNoise = float2(
            noise(uv * 1.0 + time * 0.05),
            noise(uv * 1.0 + time * 0.05 + 100.0)
        ) * 0.15;  // 减小偏移量
        float2 distortedPos = worldPos + globalNoise;
        
        // === 主波浪（2个大波）===
        
        // 主波浪1 - 主风向
        float noise1 = noise(uv * 0.3 + time * 0.03);  // 降低频率
        totalWave += GerstnerWave(
            distortedPos + noise1 * 0.2,  // 减小扰动
            windDir, 
            10.0 + noise1 * 1.0,  // 增大波长，更平缓
            waveHeight * (0.55 + noise1 * 0.1),  // 减小变化范围
            0.25 + noise1 * 0.05,  // 降低陡峭度
            speed * (0.95 + noise1 * 0.1), 
            time
        );
        
        // 主波浪2 - 偏转30度（减小角度差异）
        float angle1 = 0.523599; // 30度
        float2 dir2 = float2(
            windDir.x * cos(angle1) - windDir.y * sin(angle1),
            windDir.x * sin(angle1) + windDir.y * cos(angle1)
        );
        float noise2 = noise(uv * 0.35 + time * 0.035 + 50.0);
        totalWave += GerstnerWave(
            distortedPos + noise2 * 0.15, 
            normalize(dir2 + float2(noise2 * 0.1, 0.0)), 
            8.5 + noise2 * 0.8,  // 增大波长
            waveHeight * (0.4 + noise2 * 0.08), 
            0.22 + noise2 * 0.05, 
            speed * 1.05, 
            time
        );
        
        // === 中等波浪（3个中波，更平缓）===
        
        for (int i = 0; i < 3; i++)  // 从4减到3
        {
            float offset = float(i) * 123.456;
            float angleOffset = float(i) * 2.0944; // 每个相差120度
            float noiseVal = noise(uv * (0.8 + i * 0.2) + time * 0.04 + offset);  // 降低频率
            
            float2 dir = float2(
                cos(angleOffset + noiseVal * 0.3),  // 减小噪声影响
                sin(angleOffset + noiseVal * 0.3)
            );
            
            totalWave += GerstnerWave(
                distortedPos + noiseVal * 0.3,  // 减小扰动
                normalize(dir + windDir * 0.4), 
                5.0 + noiseVal * 1.0 + i * 0.3,  // 增大波长
                waveHeight * (0.18 + noiseVal * 0.06) * (1.0 - i * 0.08), 
                0.18 + noiseVal * 0.04,  // 降低陡峭度
                speed * (1.15 + i * 0.1), 
                time + offset * 0.1
            );
        }
        
        // === 小尺度细节（2个，轻微点缀）===
        
        for (int j = 0; j < 2; j++)  // 从6减到2
        {
            float jOffset = float(j) * 234.567;
            float jAngle = float(j) * 3.14159;  // 相差180度
            float jNoise = noise(uv * (2.0 + j * 0.5) + time * 0.06);  // 降低频率，不用turbulence
            
            float2 jDir = float2(
                cos(jAngle + jNoise * 0.3),
                sin(jAngle + jNoise * 0.3)
            );
            
            totalWave += GerstnerWave(
                worldPos + jNoise * 0.4,  // 减小扰动
                normalize(jDir), 
                2.5 + jNoise * 0.5 + j * 0.3,  // 增大波长
                waveHeight * (0.1 + jNoise * 0.03) * (1.1 - j * 0.1), 
                0.15 + jNoise * 0.03,  // 降低陡峭度
                speed * (1.3 + j * 0.15), 
                time + jOffset * 0.15
            );
        }
        
        // === 微细节（极轻微，仅作点缀）===
        float microWave = noise(worldPos * 6.0 + time * 0.3) * 0.008;  // 大幅降低频率和强度
        totalWave.z += microWave * waveHeight;
        
        return totalWave;
    }

    // --- 正弦波叠加（平缓版：低频细节）---
    float SineWavePattern(float2 uv, float time, float scale, float speed)
    {
        float2 p = uv * scale;
        float wave = 0.0;
        
        // 轻微噪声扰动
        float2 distortion = float2(
            noise(p * 0.3 + time * 0.05),  // 降低频率
            noise(p * 0.3 + time * 0.05 + 50.0)
        ) * 0.2;  // 减小强度
        float2 distortedP = p + distortion;
        
        // 大尺度平缓波
        wave += sin(distortedP.x * 1.2 + time * speed + noise(p * 0.2) * 1.5) * 0.35;
        wave += sin(distortedP.y * 1.8 - time * speed * 1.1 + noise(p * 0.25) * 1.2) * 0.3;
        
        // 交叉波（降低频率）
        float crossWave1 = sin((distortedP.x + distortedP.y) * 2.0 + time * speed * 0.8);
        float crossWave2 = sin((distortedP.x - distortedP.y) * 2.5 - time * speed * 1.0);
        wave += (crossWave1 + crossWave2) * 0.12;
        
        // 少量中频细节（从5层减到2层）
        for (int i = 0; i < 2; i++)
        {
            float freq = 3.0 + float(i) * 1.5;  // 降低频率
            float amp = 0.08 / (float(i) + 1.0);  // 降低振幅
            float phase = time * speed * (1.0 + float(i) * 0.2);
            float noisePhase = noise(p * (0.5 + i * 0.3)) * 3.14;  // 简化噪声
            
            wave += sin(distortedP.x * freq + phase + noisePhase) * amp;
            wave += cos(distortedP.y * freq * 1.1 - phase * 0.9) * amp * 0.7;
        }
        
        // 轻微的径向细节
        float2 center = frac(p * 0.2 + time * 0.03);  // 降低频率
        float dist = length(center - 0.5);
        wave += sin(dist * 12.0 - time * speed * 1.5) * exp(-dist * 2.5) * 0.06;  // 降低强度
        
        return wave / 1.3; // 归一化
    }

    // --- 噪声函数（用于扰动波纹）---
    float noise(float2 p)
    {
        float2 i = floor(p);
        float2 f = frac(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        
        return lerp(lerp(dot(hash2(i + float2(0.0, 0.0)), f - float2(0.0, 0.0)),
                         dot(hash2(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
                    lerp(dot(hash2(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)),
                         dot(hash2(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x), u.y);
    }
    
    // --- 湍流噪声 (多层噪声叠加) ---
    float turbulence(float2 p, int octaves)
    {
        float value = 0.0;
        float amplitude = 1.0;
        float frequency = 1.0;
        
        for (int i = 0; i < octaves; i++)
        {
            value += abs(noise(p * frequency)) * amplitude;
            frequency *= 2.0;
            amplitude *= 0.5;
        }
        
        return value;
    }

    // --- 物理交互波纹计算（添加噪声扰动）---
    // 基于距离的波纹扩散，模拟碰撞点产生的水波
    // 参数:
    //   uv: 当前UV坐标
    //   impactPos: 碰撞点的UV坐标
    //   impactTime: 碰撞发生的时间
    //   currentTime: 当前时间
    //   strength: 波纹强度
    // 返回: 波纹的高度贡献
    float CalculateRipple(
        float2 uv, 
        float2 impactPos, 
        float impactTime, 
        float currentTime, 
        float strength)
    {
        float elapsedTime = currentTime - impactTime;
        
        // 如果时间还没到或者太久了，不产生波纹
        if (elapsedTime < 0.0 || elapsedTime > 5.0)
            return 0.0;
        
        // 添加轻微噪声扰动到碰撞点位置
        float2 noiseOffset = float2(
            noise(impactPos * 5.0 + float2(impactTime * 0.3, 0.0)),  // 降低频率
            noise(impactPos * 5.0 + float2(0.0, impactTime * 0.3))
        ) * 0.03; // 减小偏移量
        
        float2 distortedImpactPos = impactPos + noiseOffset;
        float dist = length(uv - distortedImpactPos);
        
        // 轻微的角度噪声
        float angle = atan2(uv.y - distortedImpactPos.y, uv.x - distortedImpactPos.x);
        float angleNoise = noise(float2(angle * 2.0, impactTime)) * 0.08;  // 减小扰动
        dist += angleNoise;
        
        // 波纹传播速度 - 大幅降低（从2.0降到0.8）
        float speedVariation = 1.0 + noise(impactPos * 3.0) * 0.1;  // 减小随机变化
        float waveSpeed = 0.8 * speedVariation;  // 降低基础速度
        float wavefront = elapsedTime * waveSpeed;
        
        // 波纹宽度 - 随距离和时间变化
        float waveWidth = 0.5 + noise(float2(dist * 2.0, elapsedTime)) * 0.2;
        
        // 距离衰减
        float distAtten = 1.0 / (1.0 + dist * 0.5);
        
        // 时间衰减 - 添加噪声让衰减不那么线性
        float timeAttenBase = 1.0 - saturate(elapsedTime / 5.0);
        float timeAttenNoise = noise(float2(dist, elapsedTime * 0.5)) * 0.1;
        float timeAtten = saturate(timeAttenBase + timeAttenNoise);
        
        // 波形函数 - 使用Gabor波 + 噪声扰动
        float waveDist = abs(dist - wavefront);
        float wave = 0.0;
        
        if (waveDist < waveWidth)
        {
            // 轻微相位扰动
            float phaseNoise = noise(uv * 4.0 + float2(elapsedTime * 0.15, 0.0)) * 0.2;  // 降低频率和强度
            float phase = (dist - wavefront + phaseNoise) * 6.28;
            
            // 主波 - 轻微幅度调制
            float amplitudeModulation = 1.0 + noise(uv * 6.0 + elapsedTime) * 0.15;  // 降低调制强度
            wave = sin(phase) * exp(-waveDist * 3.0) * amplitudeModulation;
            
            // 次级波（降低频率）
            float detailPhase = phase * 1.5 + noise(uv * 8.0) * 1.5;  // 简化，降低频率
            wave += sin(detailPhase) * 0.2 * exp(-waveDist * 5.0);  // 降低强度
            
            // 轻微方向性扰动
            float directionalNoise = noise(float2(angle * 1.5, dist * 2.0)) * 0.1;  // 降低强度
            wave += directionalNoise * exp(-waveDist * 4.0);
        }
        
        // 轻微的外围细节
        float microRipple = sin(dist * 25.0 - elapsedTime * 5.0) *  // 降低频率
                           exp(-abs(dist - wavefront) * 8.0) * 
                           noise(uv * 15.0 + elapsedTime) * 0.08;  // 降低强度
        wave += microRipple;
        
        return wave * strength * distAtten * timeAtten;
    }

    // --- 多个波纹叠加（修改为接受独立参数）---
    float GetAllRipples(
        float2 uv,
        float currentTime,
        int rippleCount,
        float2 ripplePos0,
        float2 ripplePos1,
        float2 ripplePos2,
        float2 ripplePos3,
        float rippleTime0,
        float rippleTime1,
        float rippleTime2,
        float rippleTime3,
        float rippleStrength)
    {
        float totalRipple = 0.0;
        
        // 手动展开循环，处理每个波纹
        if (rippleCount >= 1 && rippleTime0 > -999.0)
        {
            totalRipple += CalculateRipple(uv, ripplePos0, rippleTime0, currentTime, rippleStrength);
        }
        
        if (rippleCount >= 2 && rippleTime1 > -999.0)
        {
            totalRipple += CalculateRipple(uv, ripplePos1, rippleTime1, currentTime, rippleStrength);
        }
        
        if (rippleCount >= 3 && rippleTime2 > -999.0)
        {
            totalRipple += CalculateRipple(uv, ripplePos2, rippleTime2, currentTime, rippleStrength);
        }
        
        if (rippleCount >= 4 && rippleTime3 > -999.0)
        {
            totalRipple += CalculateRipple(uv, ripplePos3, rippleTime3, currentTime, rippleStrength);
        }
        
        return totalRipple;
    }

    // --- 菲涅尔效果计算 (用于材质系统) ---
    // 虽然这个通常在材质编辑器中计算，但这里提供辅助函数
    float FresnelSchlick(float3 viewDir, float3 normal, float power)
    {
        float cosTheta = saturate(dot(viewDir, normal));
        return pow(1.0 - cosTheta, power);
    }

    // --- 折射扰动计算 ---
    // 返回UV偏移量，用于扰动折射采样
    float2 RefractionOffset(float3 normal, float strength)
    {
        return normal.xy * strength;
    }

    // --- 泡沫计算 (基于波峰检测) ---
    float CalculateFoam(float waveHeight, float threshold)
    {
        // 波峰处产生泡沫
        float foam = smoothstep(threshold, threshold + 0.1, waveHeight);
        return foam;
    }
};

WaterTool Tool;

// ==================== 主函数 ====================

// 1. 计算Gerstner波
float3 gerstnerWave = Tool.GetGerstnerWaves(
    UV, 
    Time, 
    WaveScale, 
    WaveSpeed, 
    WaveHeight, 
    WindDirection
);

// 2. 添加正弦波细节
float sineDetail = Tool.SineWavePattern(UV, Time, WaveScale * 2.0, WaveSpeed) * 0.1;

// 3. 计算物理交互波纹（传递独立参数）
float ripples = Tool.GetAllRipples(
    UV,
    Time,
    RippleCount,
    RipplePos0,
    RipplePos1,
    RipplePos2,
    RipplePos3,
    RippleTime0,
    RippleTime1,
    RippleTime2,
    RippleTime3,
    RippleStrength
);

// 4. 合成总高度
float totalHeight = gerstnerWave.z + sineDetail + ripples * WaveHeight;

// 5. 法线计算 (使用差分法)
float eps = 0.01;

// 计算右侧点的高度
float3 gw_right = Tool.GetGerstnerWaves(UV + float2(eps, 0.0), Time, WaveScale, WaveSpeed, WaveHeight, WindDirection);
float sd_right = Tool.SineWavePattern(UV + float2(eps, 0.0), Time, WaveScale * 2.0, WaveSpeed) * 0.1;
float rp_right = Tool.GetAllRipples(UV + float2(eps, 0.0), Time, RippleCount, RipplePos0, RipplePos1, RipplePos2, RipplePos3, RippleTime0, RippleTime1, RippleTime2, RippleTime3, RippleStrength);
float h_right = gw_right.z + sd_right + rp_right * WaveHeight;

// 计算上侧点的高度
float3 gw_up = Tool.GetGerstnerWaves(UV + float2(0.0, eps), Time, WaveScale, WaveSpeed, WaveHeight, WindDirection);
float sd_up = Tool.SineWavePattern(UV + float2(0.0, eps), Time, WaveScale * 2.0, WaveSpeed) * 0.1;
float rp_up = Tool.GetAllRipples(UV + float2(0.0, eps), Time, RippleCount, RipplePos0, RipplePos1, RipplePos2, RipplePos3, RippleTime0, RippleTime1, RippleTime2, RippleTime3, RippleStrength);
float h_up = gw_up.z + sd_up + rp_up * WaveHeight;

// 计算偏导数
float dX = (h_right - totalHeight) / eps;
float dY = (h_up - totalHeight) / eps;

// 构建法线 (考虑Gerstner波的水平位移)
float3 tangent = normalize(float3(1.0 + gerstnerWave.x, 0.0, dX));
float3 bitangent = normalize(float3(0.0, 1.0 + gerstnerWave.y, dY));
float3 normal = normalize(cross(bitangent, tangent));

// 应用法线强度
normal = normalize(float3(normal.xy * NormalStrength, normal.z));

// 6. 输出
// XYZ = Normal (世界空间或切线空间，根据需要调整)
// W = Height (用于顶点位移或其他用途)
return float4(normal, totalHeight);
