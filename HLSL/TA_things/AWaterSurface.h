// AWaterSurface.h
// 水面Actor类 - 支持物理交互波纹和动态材质更新
// 使用 MPC_Water 进行材质参数传递

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "AWaterSurface.generated.h"

// 波纹数据结构
USTRUCT(BlueprintType)
struct FRippleData
{
    GENERATED_BODY()

    // UV空间位置 (0-1范围)
    UPROPERTY(BlueprintReadWrite, Category = "Water|Ripples")
    FVector2D Position;

    // 波纹触发时间 (游戏时间秒数)
    UPROPERTY(BlueprintReadWrite, Category = "Water|Ripples")
    float TriggerTime;

    // 波纹强度倍率
    UPROPERTY(BlueprintReadWrite, Category = "Water|Ripples")
    float Strength;

    // 是否当前活跃
    UPROPERTY(BlueprintReadWrite, Category = "Water|Ripples")
    bool bIsActive;

    FRippleData()
        : Position(FVector2D(-999.0f, -999.0f))
        , TriggerTime(-999.0f)
        , Strength(1.0f)
        , bIsActive(false)
    {}
};

/**
 * 水面Actor类
 * 功能：
 * - 管理水面网格渲染
 * - 处理物理碰撞触发波纹
 * - 通过MPC更新材质参数
 * - 支持多个同时存在的波纹（最多4个）
 */
UCLASS(Blueprintable, ClassGroup = (Water), meta = (BlueprintSpawnableComponent))
class YOURPROJECT_API AWaterSurface : public AActor
{
    GENERATED_BODY()

public:
    AWaterSurface();

protected:
    virtual void BeginPlay() override;

public:
    virtual void Tick(float DeltaTime) override;
    virtual void PostInitializeComponents() override;

    // ==================== 组件 ====================

    // 水面静态网格组件
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Water|Components")
    class UStaticMeshComponent* WaterMesh;

    // ==================== 材质参数 ====================

    // Material Parameter Collection 引用
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Material")
    class UMaterialParameterCollection* WaterMPC;

    // 动态材质实例（可选，用于预览）
    UPROPERTY(BlueprintReadOnly, Category = "Water|Material")
    class UMaterialInstanceDynamic* DynamicMaterial;

    // ==================== 波浪参数 ====================

    // 波浪缩放
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Waves", meta = (ClampMin = "0.1", ClampMax = "20.0"))
    float WaveScale;

    // 波浪速度
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Waves", meta = (ClampMin = "0.0", ClampMax = "5.0"))
    float WaveSpeed;

    // 波浪高度
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Waves", meta = (ClampMin = "0.0", ClampMax = "2.0"))
    float WaveHeight;

    // 风向
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Waves")
    FVector2D WindDirection;

    // 法线强度
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Waves", meta = (ClampMin = "0.0", ClampMax = "5.0"))
    float NormalStrength;

    // ==================== 波纹参数 ====================

    // 波纹池（最多4个同时存在）
    UPROPERTY(BlueprintReadOnly, Category = "Water|Ripples")
    TArray<FRippleData> RipplePool;

    // 最大波纹数量
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Ripples", meta = (ClampMin = "1", ClampMax = "4"))
    int32 MaxRipples;

    // 波纹持续时间（秒）
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Ripples", meta = (ClampMin = "1.0", ClampMax = "10.0"))
    float RippleLifetime;

    // 全局波纹强度倍率
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Ripples", meta = (ClampMin = "0.0", ClampMax = "5.0"))
    float RippleStrength;

    // ==================== 碰撞设置 ====================

    // 是否启用碰撞触发波纹
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Collision")
    bool bEnableCollisionRipples;

    // 碰撞力度转换系数（冲量大小除以此值得到波纹强度）
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Collision", meta = (ClampMin = "100.0", ClampMax = "100000.0"))
    float ImpulseToStrengthScale;

    // 波纹强度范围限制
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Collision")
    FVector2D StrengthClampRange;

    // ==================== 调试选项 ====================

    // 是否显示调试信息
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Debug")
    bool bShowDebugInfo;

    // 是否绘制波纹位置
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Debug")
    bool bDrawRipplePositions;

    // 调试球体半径
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Water|Debug", meta = (ClampMin = "10.0", ClampMax = "200.0"))
    float DebugSphereRadius;

    // ==================== 公共方法 ====================

    /**
     * 在指定世界坐标位置添加波纹
     * @param WorldLocation 世界空间位置
     * @param Strength 波纹强度（默认1.0）
     * @return 是否成功添加
     */
    UFUNCTION(BlueprintCallable, Category = "Water|Ripples")
    bool AddRipple(const FVector& WorldLocation, float Strength = 1.0f);

    /**
     * 在指定UV坐标添加波纹
     * @param UV UV坐标 (0-1范围)
     * @param Strength 波纹强度
     * @return 是否成功添加
     */
    UFUNCTION(BlueprintCallable, Category = "Water|Ripples")
    bool AddRippleAtUV(const FVector2D& UV, float Strength = 1.0f);

    /**
     * 清除所有波纹
     */
    UFUNCTION(BlueprintCallable, Category = "Water|Ripples")
    void ClearAllRipples();

    /**
     * 世界坐标转UV坐标
     * @param WorldLocation 世界空间位置
     * @return UV坐标 (0-1范围)
     */
    UFUNCTION(BlueprintCallable, BlueprintPure, Category = "Water|Ripples")
    FVector2D WorldToUV(const FVector& WorldLocation) const;

    /**
     * UV坐标转世界坐标
     * @param UV UV坐标 (0-1范围)
     * @return 世界空间位置（Z=0平面）
     */
    UFUNCTION(BlueprintCallable, BlueprintPure, Category = "Water|Ripples")
    FVector UVToWorld(const FVector2D& UV) const;

    /**
     * 获取当前活跃波纹数量
     */
    UFUNCTION(BlueprintCallable, BlueprintPure, Category = "Water|Ripples")
    int32 GetActiveRippleCount() const;

    /**
     * 手动更新材质参数（通常在Tick中自动调用）
     */
    UFUNCTION(BlueprintCallable, Category = "Water|Material")
    void UpdateMaterialParameters();

protected:
    // ==================== 内部方法 ====================

    /**
     * 碰撞事件处理（Hit）
     */
    UFUNCTION()
    void OnWaterHit(UPrimitiveComponent* HitComponent, AActor* OtherActor,
                    UPrimitiveComponent* OtherComp, FVector NormalImpulse,
                    const FHitResult& Hit);

    /**
     * 重叠事件处理（Overlap）
     */
    UFUNCTION()
    void OnWaterBeginOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor,
                             UPrimitiveComponent* OtherComp, int32 OtherBodyIndex,
                             bool bFromSweep, const FHitResult& SweepResult);

    /**
     * 初始化MPC引用
     */
    void InitializeMPC();

    /**
     * 查找可用的波纹槽位
     * @return 可用槽位索引，-1表示无可用槽位
     */
    int32 FindAvailableRippleSlot();

    /**
     * 更新波纹状态（清理过期波纹）
     */
    void UpdateRippleStates(float DeltaTime);

    /**
     * 绘制调试信息
     */
    void DrawDebugInfo();

private:
    // 当前游戏时间
    float CurrentTime;

    // MPC实例缓存
    class UMaterialParameterCollectionInstance* MPCInstance;

    // 水面边界盒（用于UV转换）
    FBox WaterBounds;
};
