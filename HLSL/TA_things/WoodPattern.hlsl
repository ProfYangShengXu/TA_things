// 程序化木纹生成器 & 法线 (Procedural Wood & Normal)
// 将此代码复制到 UE5 材质编辑器的 Custom 节点中
// Output Type (输出类型): Float 4
//    XYZ: 法线 (连到 Normal 输入)
//    W:   木纹图案/高度 (连到 Base Color 的 Lerp Alpha)
// Inputs (输入引脚):
//    1. UV (float2)        - 连接 TexCoord
//    2. Scale (float)      - 噪声扭曲频率 (建议: 4.0)
//    3. RingScale (float)  - 木纹密度 (建议: 10.0)
//    4. Turbulence (float) - 扭曲强度 (建议: 1.5)
//    5. NormalStrength (float) - 法线强度 (建议: 1.0 ~ 5.0)

struct WoodTool
{
    // --- 随机哈希 ---
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

    // --- 封装核心生成逻辑 ---
    // 为了计算法线，我们需要计算一个点及其周围点的木纹值，所以封装成函数方便调用
    float GetWood(float2 uv, float s, float rs, float t)
    {
        float2 p = uv * s;
        float n = noise(p);
        
        // [新增] 频率调制：利用低频噪声让年轮疏密产生随机变化
        // 乘以 0.2 采样低频，让疏密变化更自然大块
        float densityVar = noise(p * 0.2);
        // 让年轮密度在 0.4倍 到 1.6倍 之间波动，打破均匀感
        float localRS = rs * (1.0 + 0.6 * densityVar);

        // 核心公式: 扭曲后的 X 轴距离 (竖纹)
        float dist = (p.x + n * t) * localRS;
        
        // 原始波形: (sin(dist) + 1.0) * 0.5
        float wave = (sin(dist) + 1.0) * 0.5;

        // [修改] 增大灰黑区域：
        // 1. 使用 pow(..., 2.0) 极大地加宽暗部 (指数越高，谷底越宽)
        // 2. 乘以 3.0 提亮整体，让波峰迅速达到顶部，保持平坦区的面积
        float height = pow(wave, 2.0) * 3.0;

        // [保留] 顶部硬截断：限制最高区域
        // 超过 0.9 的高度全部被“刨平”为 0.9。
        return min(height, 0.7);
    }
};

WoodTool Tool;

// 1. 计算当前点的木纹 (作为高度/颜色掩码)
float h = Tool.GetWood(UV, Scale, RingScale, Turbulence);

// 2. 法线计算 (Sobel 算子 - 改良抗锯齿版)
// [修复条带伪影]: 增大采样间距 eps，平滑高频噪点
float eps = 0.02; 

// 使用 4 点采样 (Sobel) 以获得更平稳的斜率，避免侧光下的摩尔纹
float h_left  = Tool.GetWood(UV + float2(-eps, 0.0), Scale, RingScale, Turbulence);
float h_right = Tool.GetWood(UV + float2(eps, 0.0), Scale, RingScale, Turbulence);
float h_down  = Tool.GetWood(UV + float2(0.0, -eps), Scale, RingScale, Turbulence);
float h_up    = Tool.GetWood(UV + float2(0.0, eps), Scale, RingScale, Turbulence);

// 计算中心差分斜率
float dX = (h_right - h_left) * 0.5; 
float dY = (h_up - h_down) * 0.5;

// [修复条带伪影]: 软限制最大斜率
// 归一化斜率并限制范围，防止法线过于陡峭导致阴影计算错误
dX = dX / (eps + 0.001);
dY = dY / (eps + 0.001);

float slopeLimit = 10.0;
dX = clamp(dX, -slopeLimit, slopeLimit);
dY = clamp(dY, -slopeLimit, slopeLimit);

// 3. 构建法线
float3 normal = normalize(float3(-dX * NormalStrength, -dY * NormalStrength, 1.0));

// 3. 输出打包结果
// XYZ = Normal, W = Wood Pattern
return float4(normal, h);
