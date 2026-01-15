// 柏林噪声与法线贴图生成器 (FBM多层叠加版)
// 将此代码复制到 UE5 材质编辑器的 Custom 节点中
// 下面是使用说明：
// Output Type (输出类型): 选择 Float 4
// Inputs (输入引脚): 需要你在 Custom 节点上手动添加以下三个输入:
//    1. UV (float2)            - 连接 TexCoord 节点，控制纹理坐标
//    2. Scale (float)          - 连接一个数值，控制噪声的疏密程度 (建议值: 3.0)
//    3. NormalStrength (float) - 连接一个数值，控制法线凹凸的强度 (建议值: 1.0)

// 定义一个结构体来封装噪声函数，防止函数名污染
struct NoiseGenerator
{
    // --- 哈希函数 (随机数生成) ---
    // 输入一个坐标 p，返回一个伪随机的二维向量
    // 原理是利用 sin 函数的大数计算产生混乱值
    float2 hash(float2 p)
    {
        // 这一步是让坐标与两个大质数向量点积，打乱坐标规律
        p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
        // 这里生成 -1.0 到 1.0 之间的随机值
        // sin(p) * 43758.5453 也是一个经典的随机数魔法数字
        return -1.0 + 2.0 * frac(sin(p) * 43758.5453123);
    }

    // --- 梯度噪声 (Gradient Noise) ---
    // 这是柏林噪声的核心，生成单层平滑的噪声
    float noise(float2 p)
    {
        float2 i = floor(p); // 获取坐标的整数部分 (晶格左下角)
        float2 f = frac(p);  // 获取坐标的小数部分 (晶格内部位置)

        // 平滑曲线函数 (缓动函数): u = f * f * (3.0 - 2.0 * f)
        // 它可以让晶格之间的过渡更平滑，消除棱角
        float2 u = f * f * (3.0 - 2.0 * f);

        // 双线性插值计算
        // 计算晶格四个顶点的随机向量与距离向量的点积，然后混合
        return lerp(lerp(dot(hash(i + float2(0.0, 0.0)), f - float2(0.0, 0.0)),
                         dot(hash(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
                    lerp(dot(hash(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)),
                         dot(hash(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x), u.y);
    }

    // --- 分形布朗运动 (FBM) ---
    // 原理：把多个不同频率(疏密)和振幅(强度)的噪声叠加在一起
    // 就像大山(低频高振幅)上面有石头(中频中振幅)，石头上有沙砾(高频低振幅)
    float fbm(float2 p)
    {
        float value = 0.0;
        float amplitude = 0.5; // 初始振幅 (强度)
        float frequency = 1.0; // 初始频率 (疏密)
        
        // 循环 5 次叠加 (这叫 5个 Octaves/倍频程)
        // 想要更多细节可以增加循环次数，但性能开销会变大
        for (int i = 0; i < 5; i++)
        {
            value += amplitude * noise(p * frequency);
            frequency *= 2.0; // 每次频率翻倍 (更密)
            amplitude *= 0.5; // 每次强度减半 (细节更微小)
        }
        return value;
    }
};

// 实例化我们的生成器
NoiseGenerator Gen;

// 将输入的 UV 乘以 Scale 参数，放大坐标系，决定噪声的整体密度
float2 p = UV * Scale;

// --- 第一步：计算高度 (用于 Base Color) ---
// FBM 返回的结果大约在 -1 到 1 之间
// 我们做一个映射：0.5 + 0.5 * 结果，把它变成 0 到 1 的灰度值
float h = 0.5 + 0.5 * Gen.fbm(p);

// --- 第二步：计算法线 (Normal Map) ---
// 原理：差分法。我们需要知道当前点周围是高还是低，才能决定法线朝向。
// 我们在当前点右边一点点(eps)和上边一点点(eps)的地方再采样两次噪声。
float eps = 0.001; // 采样偏移距离，越小越精确，但太小会有精度问题
float h_right = 0.5 + 0.5 * Gen.fbm(p + float2(eps, 0.0)); // 右边点的高度
float h_up    = 0.5 + 0.5 * Gen.fbm(p + float2(0.0, eps)); // 上边点的高度

// 计算坡度 (斜率)
// dX 就是水平方向的高度变化率
// dY 就是垂直方向的高度变化率
float dX = (h_right - h) / eps;
float dY = (h_up - h) / eps;

// 构建切线空间法线 (Tangent Space Normal)
// 默认平坦的法线是 (0, 0, 1)。如果有坡度，xy 分量就会偏移。
// 乘以 -NormalStrength 是为了控制凹凸感的强度，负号是为了符合法线贴图的左手/右手坐标系规范
float3 normal = normalize(float3(-dX * NormalStrength, -dY * NormalStrength, 1.0));

// --- 第三步：输出结果 ---
// 返回一个 float4 向量
// XYZ 通道存的是法线 (连到 Normal)
// W (Alpha) 通道存的是高度/颜色 (连到 BaseColor 或 Roughness)
return float4(normal, h);
