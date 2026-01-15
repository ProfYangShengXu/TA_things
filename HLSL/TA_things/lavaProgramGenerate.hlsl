// 程序化岩浆生成器 (Flowing Lava & Normal)
// Output Type: Float 4
//    XYZ: 法线 (连 Normal)
//    W:   热度 Mask (连 BaseColor/Emissive 的 Lerp Alpha)
// Inputs: UV, Time, Scale (3.0), Speed (0.2), NormalStrength (1.0)

struct LavaTool
{
    // --- 基础哈希 ---
    float2 hash(float2 p)
    {
        p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
        return -1.0 + 2.0 * frac(sin(p) * 43758.5453123);
    }

    // --- 梯度噪声 ---
    float noise(float2 p)
    {
        float2 i = floor(p);
        float2 f = frac(p);
        float2 u = f * f * (3.0 - 2.0 * f);

        return lerp(lerp(dot(hash(i + float2(0.0, 0.0)), f - float2(0.0, 0.0)),
                         dot(hash(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
                    lerp(dot(hash(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)),
                         dot(hash(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x), u.y);
    }

    // --- FBM (改良自然版) ---
    float fbm(float2 p)
    {
        float value = 0.0;
        float amp = 0.5;
        
        // [新增] 旋转矩阵
        // 让每一层噪声都有旋转偏移，消除网格感，让岩浆的形状不再是直来直去的
        // 这里的数值对应约 37 度的旋转
        float2x2 rot = float2x2(0.8, -0.6, 0.6, 0.8) * 2.0; 

        // 恢复到 4 层，因为旋转矩阵会打散细节，不会显得太碎，反而增加自然感
        for (int i = 0; i < 4; i++)
        {
            value += amp * noise(p);
            // 手动旋转: p = mul(p, rot); 在某些 UE 版本需注意行/列向量顺序，这里直接用矩阵乘
            p = mul(p, rot); 
            amp *= 0.5;
        }
        return value;
    }

    // --- 域扭曲核心 ---
    // 返回值 -1.0 ~ 1.0
    float flow(float2 p, float t, float spd)
    {
        float2 q = float2(fbm(p), fbm(p + float2(5.2, 1.3)));
        
        float2 r = float2(fbm(p + 4.0 * q + float2(1.7, 9.2) + t * spd),
                          fbm(p + 4.0 * q + float2(8.3, 2.8) + t * spd * 1.2));

        return fbm(p + 4.0 * r);
    }

    // --- 封装获取高度/热度函数 ---
    float GetLavaHeat(float2 uv, float t, float scale, float spd)
    {
        float2 p = uv * scale;
        
        // 1. 主体流动 (Flow)
        // 范围大致在 -1.0 到 1.0
        float mainFlow = flow(p, t, spd);
        
        // 2. [关键修改] 生成“浮渣/硬壳” (Crust Mask)
        // 使用高频噪声模拟表面冷却的黑色硬块
        // 我们希望这些硬块是黑色的，并且随着流动一起漂移
        float crustNoise = noise(p * 4.0 + float2(t * 0.15, t * 0.05));
        
        // 将噪声处理成斑块状：取正值并锐化
        float crust = smoothstep(0.0, 0.8, crustNoise);

        // 3. 混合：减法模式
        // 原来的逻辑是加法(变亮)，现在改为减法(遮挡)。
        // 越是有 crust 的地方，热度越低(变黑)。
        // mainFlow * 0.5 + 0.5 将范围转为 0~1
        float heat = (mainFlow * 0.5 + 0.5);
        
        // 用硬壳遮挡热度 (0.6 是遮挡强度)
        heat -= crust * 0.6;
        
        // 4. [有机颜色变化] 扰动与重映射
        // 这一步是为了让过渡区域此时不是线性的，而是有层次的
        // 增加一点正弦扰动，让红-黄过渡区有像“丝绸”一样的细节
        heat += sin(heat * 15.0) * 0.05;

        // 5. 强力压暗 (Thresholding)
        // 只要低于 0.35 的值全部切成 0 (纯黑岩石)
        // 这会制造出大面积的黑暗区域
        heat = smoothstep(0.35, 0.85, heat);

        // 6. 最终的指数增强 (保留高光核心)
        return pow(max(0.001, heat), 2.5); 
    }
};

LavaTool Tool;

// 1. 计算中心热度 (Height/Mask)
float h = Tool.GetLavaHeat(UV, Time, Scale, Speed);

// 2. 法线计算 (差分法)
// 液体通常比较平滑，eps 不用太小
float eps = 0.1;
float h_right = Tool.GetLavaHeat(UV + float2(eps, 0.0), Time, Scale, Speed);
float h_up    = Tool.GetLavaHeat(UV + float2(0.0, eps), Time, Scale, Speed);

float dX = (h_right - h) / eps;
float dY = (h_up - h) / eps;

// 构建法线
// 注意：岩浆是流体，法线强度不要太大，否则看起来像固体石头
float3 normal = normalize(float3(-dX * NormalStrength, -dY * NormalStrength, 1.0));

// 3. 输出
// XYZ = Normal, W = Heat Mask
return float4(normal, h);r
