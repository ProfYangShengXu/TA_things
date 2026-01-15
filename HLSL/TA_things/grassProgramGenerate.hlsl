// Output Type (输出类型): Float 4
//    XYZ: 法线 (Normal) - 连到材质 Normal 插槽
//    W:   高度/遮罩 (Height) - 连到 Lerp 的 Alpha 来混合颜色
// Inputs (输入引脚):
//    1. UV (float2)        - 连接 TexCoord
//    2. Scale (float)      - 草的密度 (建议: 5.0)
//    3. Stretch (float)    - 拉伸比例，让晶格变长像草叶 (建议: 8.0 ~ 15.0)
//    4. NormalStrength (float) - 法线强度 (建议: 2.0)

struct GrassTool
{
    // --- 随机哈希 (修复版) ---
    // 之前的哈希算法在高频或特定显卡上可能会产生伪影或 NaN
    float2 hash(float2 p)
    {
        // 1. 先 frac 防止坐标过大导致 sin 精度丢失
        p = frac(p * float2(0.3183099, 0.3678794)); // 乘以 1/pi 和 1/e 避免整数规律
        p = p * 17.0 + float2(0.2, 0.4);            // 偏移

        // 2. 更稳定的随机算法，避免大数 sin 运算
        float2 r;
        r.x = frac(dot(p, float2(12.9898, 78.233)));
        r.y = frac(dot(p, float2(39.7865, 27.1724)));
        
        // 3. 再次打散
        return frac(sin(r) * 43758.5453123);
    }
    
    // 或者使用更简单的 Hash (如果不追求高质量):
    // float2 hash(float2 p) {
    //      p = float2( dot(p,float2(127.1,311.7)), dot(p,float2(269.5,183.3)) );
    //      return frac(sin(p)*43758.5453);
    // }

    // --- 沃罗诺伊/细胞噪声 (Voronoi) ---
    // 修改为支持各向异性距离 (Anisotropic Voronoi) 以实现随机旋转
    float3 voronoi(float2 x, float stretch)
    {
        float2 n = floor(x);
        float2 f = frac(x);

        float2 mg, mr;
        float md = 8.0;

        // 搜索邻域 (由于可能有较大旋转拉伸，建议扩大搜索范围，或者接受轻微截断瑕疵)
        // 草地纹理稍微乱一点没关系，3x3 够用了
        for (int j = -1; j <= 1; j++)
        {
            for (int i = -1; i <= 1; i++)
            {
                float2 g = float2(float(i), float(j));
                float2 rand = hash(n + g);
                float2 o = rand * 0.5 + 0.5;

                float2 r = g + o - f;
                
                // [重点修改] 随机旋转拉伸
                // 使用随机数 rand.y 生成一个角度 (-1.0 到 1.0 弧度，大约 +/- 57度)
                float angle = (rand.y - 0.5) * 2.0; 
                float s = sin(angle);
                float c = cos(angle);
                
                // 旋转向量 r
                float2 r_rot = float2(r.x * c - r.y * s, r.x * s + r.y * c);
                
                // 在旋转后的局部空间中拉伸 X 轴 (让草叶变细)
                // 原理：X轴每移动一点，距离增加很多 -> 导致形状在X轴很窄
                r_rot.x *= stretch; 
                
                float d = dot(r_rot, r_rot);

                if (d < md)
                {
                    md = d;
                    mr = r;
                    mg = g;
                }
            }
        }
        
        md = sqrt(md);
        return float3(md, hash(n + mg).x, 0.0);
    }

    // --- 简单梯度噪声 (新增) ---
    // 用于增加表面细节
    float noise(float2 p)
    {
        float2 i = floor(p);
        float2 f = frac(p);
        float2 u = f * f * (3.0 - 2.0 * f);

        // hash 返回 0~1，我们需要 -1~1 的梯度向量
        float2 ga = hash(i + float2(0.0, 0.0)) * 2.0 - 1.0;
        float2 gb = hash(i + float2(1.0, 0.0)) * 2.0 - 1.0;
        float2 gc = hash(i + float2(0.0, 1.0)) * 2.0 - 1.0;
        float2 gd = hash(i + float2(1.0, 1.0)) * 2.0 - 1.0;

        float va = dot(ga, f - float2(0.0, 0.0));
        float vb = dot(gb, f - float2(1.0, 0.0));
        float vc = dot(gc, f - float2(0.0, 1.0));
        float vd = dot(gd, f - float2(1.0, 1.0));

        return lerp(lerp(va, vb, u.x), lerp(vc, vd, u.x), u.y);
    }

    // 封装生成函数
    float GetGrassHeight(float2 uv, float s, float str)
    {
        // 1. [不均匀分布]
        // 使用低频噪声大幅扭曲原始 UV，导致有的区域草很密，有的区域很疏
        float2 unevenWarp = float2(noise(uv * 1.2), noise(uv * 1.2 + 5.2));
        uv += unevenWarp * 0.35;

        // 2. 基础坐标 (增加 1.5 倍密度)
        float2 p = uv * s * 1.5;

        // [强卷曲] Domain Warping
        // 使用较强的噪声场偏移坐标，产生明显的“乱草”和“卷曲”效果
        float2 curl = float2(noise(p * 0.4), noise(p * 0.4 + 2.1));
        p += curl * 1.2; 

        // 3. 计算 Voronoi (传入 stretch 参数)
        float3 v = voronoi(p, str);
        
        // 4. 形状重塑
        // 收紧边缘范围 (0.05 ~ 0.55)，让草叶之间留出更多空隙展示地面纹理
        float blade = 1.0 - smoothstep(0.05, 0.55, v.x); 
        blade = pow(blade, 2.0); // 变细，增加缝隙面积
        
        // [表面纹理噪声] 增强
        // 叠加更强的纤维纹理
        float fiber = noise(p * float2(3.0, 12.0)); 
        blade += blade * fiber * 0.4; // 噪声影响提升至 0.4

        // [缝隙纹理] 地面细节
        // 在缝隙处生成高频的噪点模拟枯草、泥土粒
        float dirtNoise = noise(p * 4.0) * 0.5 + noise(p * 10.0) * 0.2;
        float gapMask = pow(saturate(v.x), 0.5); // 越靠近边缘(缝隙)值越大
        float ground = dirtNoise * gapMask * 0.25; // 地面强度

        // 混合：取最大值，保证草叶覆盖地面
        return max(ground, blade) * (0.5 + 0.5 * v.y);
    }
};

GrassTool Tool;

// 1. 计算中心高度
float h = Tool.GetGrassHeight(UV, Scale, Stretch);

// 2. 法线计算 (Sobel 算子 - 改良抗锯齿版)
// [修复条带伪影关键点 1]: 显著增大采样间距 eps
// 侧光下的条带通常是因为法线过于高频锐利，导致渲染采样产生摩尔纹
// 增大 eps 会起到低通滤波的作用，平滑法线
float eps = 0.05; 

// [修复条带伪影关键点 2]: 使用 4 点采样 (Sobel)
// 相比之前的 2 点差分法，Sobel 能更平稳地计算平均斜率
float h_left  = Tool.GetGrassHeight(UV + float2(-eps, 0.0), Scale, Stretch);
float h_right = Tool.GetGrassHeight(UV + float2(eps, 0.0), Scale, Stretch);
float h_down  = Tool.GetGrassHeight(UV + float2(0.0, -eps), Scale, Stretch);
float h_up    = Tool.GetGrassHeight(UV + float2(0.0, eps), Scale, Stretch);

// 计算中心差分斜率
float dX = (h_right - h_left) * 0.5; 
float dY = (h_up - h_down) * 0.5;

// [修复条带伪影关键点 3]: 软限制最大斜率 (Soft Clamp)
// 之前是硬 Clamp，现在改用 tanh 或简单的除法衰减
// 这能防止法线在边缘处变得无限陡峭
dX = dX / (eps + 0.001); // 避免除零
dY = dY / (eps + 0.001);

// 强制限制斜率范围，防止掠射角下的高光爆炸
// 值越小，法线越平滑，条带越少 (-10 ~ 10 是一个比较安全的范围)
float slopeLimit = 10.0;
dX = clamp(dX, -slopeLimit, slopeLimit);
dY = clamp(dY, -slopeLimit, slopeLimit);

// 3. 构建法线
float3 normal = normalize(float3(-dX * NormalStrength, -dY * NormalStrength, 1.0));

// 4. 计算切线 (Tangent)
// 在切线空间中，默认切线是 float3(1, 0, 0)。
// 经过扰动后，切线应该垂直于法线。
// 既然我们已经有了扰动后的法线 N，我们可以通过 Gram-Schmidt 正交化来近似切线 T。
// 简单来说：Tangent = normalize(BaseTangent - Normal * dot(BaseTangent, Normal))
float3 baseTan = float3(1.0, 0.0, 0.0);
float3 tangent = normalize(baseTan - normal * dot(baseTan, normal));

// 输出配置：
// 即使我们计算了 tangent，Custom Node 只能输出一个 float4。
// 建议：
// RGB 输出 Normal (引擎最常用)
// A   输出 Height (用于上色)
// 如果你非要 Tangent，可以牺牲 Alpha 通道或者 Height 通道。
// 这里还是保持最通用的 Normal + Height 结构。
// 你可以用 Height 在材质里 Lerp(深绿, 浅绿, Height)

return float4(normal, h);
