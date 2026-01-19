// AWaterSurface.cpp
// 水面Actor类实现

#include "AWaterSurface.h"
#include "Components/StaticMeshComponent.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialParameterCollection.h"
#include "Materials/MaterialParameterCollectionInstance.h"
#include "Engine/StaticMesh.h"
#include "DrawDebugHelpers.h"
#include "Kismet/GameplayStatics.h"

// 构造函数
AWaterSurface::AWaterSurface()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.TickGroup = TG_PrePhysics; // 在物理之前更新

    // 创建水面网格组件
    WaterMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("WaterMesh"));
    RootComponent = WaterMesh;

    // 默认碰撞设置 - 使用Overlap模式
    WaterMesh->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
    WaterMesh->SetCollisionObjectType(ECC_WorldStatic);
    WaterMesh->SetCollisionResponseToAllChannels(ECR_Ignore);
    WaterMesh->SetCollisionResponseToChannel(ECC_Pawn, ECR_Overlap);
    WaterMesh->SetCollisionResponseToChannel(ECC_PhysicsBody, ECR_Overlap);
    WaterMesh->SetCollisionResponseToChannel(ECC_WorldDynamic, ECR_Overlap);
    WaterMesh->SetGenerateOverlapEvents(true);
    WaterMesh->SetNotifyRigidBodyCollision(true);

    // 默认波浪参数
    WaveScale = 5.0f;
    WaveSpeed = 0.5f;
    WaveHeight = 0.3f;
    WindDirection = FVector2D(1.0f, 0.5f);
    NormalStrength = 1.0f;

    // 默认波纹参数
    MaxRipples = 4;
    RippleLifetime = 5.0f;
    RippleStrength = 1.0f;

    // 碰撞设置
    bEnableCollisionRipples = true;
    ImpulseToStrengthScale = 10000.0f;
    StrengthClampRange = FVector2D(0.5f, 2.0f);

    // 调试选项
    bShowDebugInfo = false;
    bDrawRipplePositions = false;
    DebugSphereRadius = 50.0f;

    // 内部变量
    CurrentTime = 0.0f;
    MPCInstance = nullptr;
    WaterBounds = FBox(EForceInit::ForceInit);
}

// 组件初始化后
void AWaterSurface::PostInitializeComponents()
{
    Super::PostInitializeComponents();

    // 初始化波纹池
    RipplePool.SetNum(MaxRipples);
    for (int32 i = 0; i < MaxRipples; i++)
    {
        RipplePool[i] = FRippleData();
    }
}

// 开始游戏
void AWaterSurface::BeginPlay()
{
    Super::BeginPlay();

    // 初始化MPC
    InitializeMPC();

    // 创建动态材质实例（可选）
    if (WaterMesh && WaterMesh->GetMaterial(0))
    {
        DynamicMaterial = UMaterialInstanceDynamic::Create(WaterMesh->GetMaterial(0), this);
        WaterMesh->SetMaterial(0, DynamicMaterial);
    }

    // 绑定碰撞事件
    if (WaterMesh && bEnableCollisionRipples)
    {
        // 绑定Hit事件（用于物理对象）
        WaterMesh->OnComponentHit.AddDynamic(this, &AWaterSurface::OnWaterHit);
        
        // 绑定Overlap事件（用于更广泛的检测）
        WaterMesh->OnComponentBeginOverlap.AddDynamic(this, &AWaterSurface::OnWaterBeginOverlap);
        
        UE_LOG(LogTemp, Log, TEXT("AWaterSurface: 碰撞事件已绑定"));
    }

    // 计算水面边界
    if (WaterMesh && WaterMesh->GetStaticMesh())
    {
        FBox LocalBounds = WaterMesh->GetStaticMesh()->GetBoundingBox();
        WaterBounds = LocalBounds.TransformBy(GetActorTransform());
    }

    // 初始化MPC参数
    if (MPCInstance)
    {
        MPCInstance->SetScalarParameterValue(FName("WaveScale"), WaveScale);
        MPCInstance->SetScalarParameterValue(FName("WaveSpeed"), WaveSpeed);
        MPCInstance->SetScalarParameterValue(FName("WaveHeight"), WaveHeight);
        MPCInstance->SetScalarParameterValue(FName("NormalStrength"), NormalStrength);
        MPCInstance->SetVectorParameterValue(FName("WindDirection"), 
            FLinearColor(WindDirection.X, WindDirection.Y, 0.0f, 0.0f));
        MPCInstance->SetScalarParameterValue(FName("RippleStrength"), RippleStrength);
    }
}

// 每帧更新
void AWaterSurface::Tick(float DeltaTime)
{
    Super::Tick(DeltaTime);

    CurrentTime += DeltaTime;

    // 更新波纹状态
    UpdateRippleStates(DeltaTime);

    // 更新材质参数
    UpdateMaterialParameters();

    // 绘制调试信息
    if (bShowDebugInfo || bDrawRipplePositions)
    {
        DrawDebugInfo();
    }
}

// 初始化MPC
void AWaterSurface::InitializeMPC()
{
    if (!WaterMPC)
    {
        // 尝试加载默认MPC
        WaterMPC = LoadObject<UMaterialParameterCollection>(
            nullptr, TEXT("/Game/Materials/MPC_Water"));
        
        if (!WaterMPC)
        {
            UE_LOG(LogTemp, Error, TEXT("AWaterSurface: 未找到 MPC_Water！请在 /Game/Materials/ 创建它。"));
            return;
        }
    }

    // 获取MPC实例
    if (WaterMPC && GetWorld())
    {
        MPCInstance = GetWorld()->GetParameterCollectionInstance(WaterMPC);
        
        if (MPCInstance)
        {
            UE_LOG(LogTemp, Log, TEXT("AWaterSurface: MPC初始化成功"));
        }
        else
        {
            UE_LOG(LogTemp, Error, TEXT("AWaterSurface: 无法获取MPC实例"));
        }
    }
}

// 添加波纹（世界坐标）
bool AWaterSurface::AddRipple(const FVector& WorldLocation, float Strength)
{
    FVector2D UV = WorldToUV(WorldLocation);
    return AddRippleAtUV(UV, Strength);
}

// 添加波纹（UV坐标）
bool AWaterSurface::AddRippleAtUV(const FVector2D& UV, float Strength)
{
    // 验证UV范围
    if (UV.X < -0.5f || UV.X > 1.5f || UV.Y < -0.5f || UV.Y > 1.5f)
    {
        if (bShowDebugInfo)
        {
            UE_LOG(LogTemp, Warning, TEXT("AWaterSurface: 波纹UV超出范围 (%f, %f)"), UV.X, UV.Y);
        }
        return false;
    }

    // 查找可用槽位
    int32 SlotIndex = FindAvailableRippleSlot();
    if (SlotIndex == -1)
    {
        if (bShowDebugInfo)
        {
            UE_LOG(LogTemp, Warning, TEXT("AWaterSurface: 无可用波纹槽位"));
        }
        return false;
    }

    // 设置波纹数据
    RipplePool[SlotIndex].Position = UV;
    RipplePool[SlotIndex].TriggerTime = CurrentTime;
    RipplePool[SlotIndex].Strength = FMath::Clamp(Strength, 
        StrengthClampRange.X, StrengthClampRange.Y);
    RipplePool[SlotIndex].bIsActive = true;

    if (bShowDebugInfo)
    {
        UE_LOG(LogTemp, Log, TEXT("AWaterSurface: 添加波纹 [槽位%d] UV(%f,%f) 强度%.2f"), 
            SlotIndex, UV.X, UV.Y, Strength);
    }

    return true;
}

// 清除所有波纹
void AWaterSurface::ClearAllRipples()
{
    for (FRippleData& Ripple : RipplePool)
    {
        Ripple.bIsActive = false;
        Ripple.Position = FVector2D(-999.0f, -999.0f);
        Ripple.TriggerTime = -999.0f;
    }

    UE_LOG(LogTemp, Log, TEXT("AWaterSurface: 清除所有波纹"));
}

// 世界坐标转UV
FVector2D AWaterSurface::WorldToUV(const FVector& WorldLocation) const
{
    if (!WaterMesh || !WaterMesh->GetStaticMesh())
    {
        return FVector2D::ZeroVector;
    }

    // 转换到局部空间
    FVector LocalPos = GetActorTransform().InverseTransformPosition(WorldLocation);

    // 获取网格边界
    FBox LocalBounds = WaterMesh->GetStaticMesh()->GetBoundingBox();

    // 归一化到0-1
    float U = (LocalPos.X - LocalBounds.Min.X) / (LocalBounds.Max.X - LocalBounds.Min.X);
    float V = (LocalPos.Y - LocalBounds.Min.Y) / (LocalBounds.Max.Y - LocalBounds.Min.Y);

    return FVector2D(U, V);
}

// UV转世界坐标
FVector AWaterSurface::UVToWorld(const FVector2D& UV) const
{
    if (!WaterMesh || !WaterMesh->GetStaticMesh())
    {
        return FVector::ZeroVector;
    }

    // 获取网格边界
    FBox LocalBounds = WaterMesh->GetStaticMesh()->GetBoundingBox();

    // UV反归一化到局部空间
    float LocalX = FMath::Lerp(LocalBounds.Min.X, LocalBounds.Max.X, UV.X);
    float LocalY = FMath::Lerp(LocalBounds.Min.Y, LocalBounds.Max.Y, UV.Y);
    FVector LocalPos(LocalX, LocalY, 0.0f);

    // 转换到世界空间
    return GetActorTransform().TransformPosition(LocalPos);
}

// 获取活跃波纹数量
int32 AWaterSurface::GetActiveRippleCount() const
{
    int32 Count = 0;
    for (const FRippleData& Ripple : RipplePool)
    {
        if (Ripple.bIsActive)
        {
            Count++;
        }
    }
    return Count;
}

// 更新材质参数
void AWaterSurface::UpdateMaterialParameters()
{
    if (!MPCInstance)
    {
        return;
    }

    // 更新时间
    MPCInstance->SetScalarParameterValue(FName("CurrentTime"), CurrentTime);

    // 计算活跃波纹数
    int32 ActiveCount = GetActiveRippleCount();
    MPCInstance->SetScalarParameterValue(FName("RippleCount"), (float)ActiveCount);

    // 更新每个波纹的参数
    for (int32 i = 0; i < MaxRipples; i++)
    {
        FName PosParamName = FName(*FString::Printf(TEXT("RipplePos%d"), i));
        FName TimeParamName = FName(*FString::Printf(TEXT("RippleTime%d"), i));

        if (i < RipplePool.Num() && RipplePool[i].bIsActive)
        {
            FLinearColor PosColor(
                RipplePool[i].Position.X,
                RipplePool[i].Position.Y,
                0.0f, 0.0f
            );
            MPCInstance->SetVectorParameterValue(PosParamName, PosColor);
            MPCInstance->SetScalarParameterValue(TimeParamName, RipplePool[i].TriggerTime);
        }
        else
        {
            // 设置无效值
            MPCInstance->SetVectorParameterValue(PosParamName, 
                FLinearColor(-999.0f, -999.0f, 0.0f, 0.0f));
            MPCInstance->SetScalarParameterValue(TimeParamName, -999.0f);
        }
    }
}

// 碰撞事件处理（Hit）
void AWaterSurface::OnWaterHit(UPrimitiveComponent* HitComponent, AActor* OtherActor,
                                UPrimitiveComponent* OtherComp, FVector NormalImpulse,
                                const FHitResult& Hit)
{
    if (!OtherActor || OtherActor == this || !bEnableCollisionRipples)
    {
        return;
    }

    // 计算碰撞强度
    float ImpulseMagnitude = NormalImpulse.Size();
    float Strength = ImpulseMagnitude / ImpulseToStrengthScale;
    
    // 如果冲量为0（可能是静态接触），使用默认强度
    if (ImpulseMagnitude < 0.01f)
    {
        Strength = 1.0f;
    }
    
    Strength = FMath::Clamp(Strength, StrengthClampRange.X, StrengthClampRange.Y);

    // 添加波纹
    AddRipple(Hit.ImpactPoint, Strength);

    if (bShowDebugInfo)
    {
        UE_LOG(LogTemp, Warning, TEXT("AWaterSurface: Hit触发波纹 - Actor:%s 冲量:%.2f 强度:%.2f"),
            *OtherActor->GetName(), ImpulseMagnitude, Strength);
    }
}

// 重叠事件处理（Overlap）
void AWaterSurface::OnWaterBeginOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor,
                                         UPrimitiveComponent* OtherComp, int32 OtherBodyIndex,
                                         bool bFromSweep, const FHitResult& SweepResult)
{
    if (!OtherActor || OtherActor == this || !bEnableCollisionRipples)
    {
        return;
    }

    // 使用Overlap触发波纹
    FVector ImpactPoint;
    float Strength = 1.0f;

    if (bFromSweep && SweepResult.bBlockingHit)
    {
        // 如果是扫描碰撞，使用撞击点
        ImpactPoint = SweepResult.ImpactPoint;
        
        // 尝试根据速度计算强度
        if (OtherComp && OtherComp->IsSimulatingPhysics())
        {
            FVector Velocity = OtherComp->GetPhysicsLinearVelocity();
            float Speed = Velocity.Size();
            Strength = FMath::Clamp(Speed / 500.0f, StrengthClampRange.X, StrengthClampRange.Y);
        }
    }
    else
    {
        // 否则使用Actor位置
        ImpactPoint = OtherActor->GetActorLocation();
    }

    // 添加波纹
    AddRipple(ImpactPoint, Strength);

    if (bShowDebugInfo)
    {
        UE_LOG(LogTemp, Warning, TEXT("AWaterSurface: Overlap触发波纹 - Actor:%s 位置:%s 强度:%.2f"),
            *OtherActor->GetName(), *ImpactPoint.ToString(), Strength);
    }
}

// 查找可用槽位
int32 AWaterSurface::FindAvailableRippleSlot()
{
    // 首先查找未激活的槽位
    for (int32 i = 0; i < RipplePool.Num(); i++)
    {
        if (!RipplePool[i].bIsActive)
        {
            return i;
        }
    }

    // 如果都在使用，替换最旧的
    int32 OldestIndex = 0;
    float OldestTime = CurrentTime;

    for (int32 i = 0; i < RipplePool.Num(); i++)
    {
        if (RipplePool[i].TriggerTime < OldestTime)
        {
            OldestTime = RipplePool[i].TriggerTime;
            OldestIndex = i;
        }
    }

    return OldestIndex;
}

// 更新波纹状态
void AWaterSurface::UpdateRippleStates(float DeltaTime)
{
    for (FRippleData& Ripple : RipplePool)
    {
        if (Ripple.bIsActive)
        {
            float ElapsedTime = CurrentTime - Ripple.TriggerTime;
            
            // 检查是否过期
            if (ElapsedTime > RippleLifetime)
            {
                Ripple.bIsActive = false;
                Ripple.Position = FVector2D(-999.0f, -999.0f);
                Ripple.TriggerTime = -999.0f;
            }
        }
    }
}

// 绘制调试信息
void AWaterSurface::DrawDebugInfo()
{
    if (!GetWorld())
    {
        return;
    }

    // 绘制波纹位置
    if (bDrawRipplePositions)
    {
        for (int32 i = 0; i < RipplePool.Num(); i++)
        {
            if (RipplePool[i].bIsActive)
            {
                FVector WorldPos = UVToWorld(RipplePool[i].Position);
                WorldPos.Z += 50.0f; // 略微抬高以便观察

                // 根据剩余时间改变颜色
                float ElapsedTime = CurrentTime - RipplePool[i].TriggerTime;
                float LifeRatio = 1.0f - (ElapsedTime / RippleLifetime);
                FColor Color = FColor::MakeRedToGreenColorFromScalar(LifeRatio);

                DrawDebugSphere(GetWorld(), WorldPos, DebugSphereRadius, 
                    12, Color, false, -1.0f, 0, 2.0f);

                // 绘制索引文字
                DrawDebugString(GetWorld(), WorldPos + FVector(0, 0, 50), 
                    FString::Printf(TEXT("%d (%.1fs)"), i, LifeRatio * RippleLifetime),
                    nullptr, Color, 0.0f, true);
            }
        }
    }

    // 绘制调试文本
    if (bShowDebugInfo && GEngine)
    {
        FString DebugText = FString::Printf(
            TEXT("Water Surface Debug\n")
            TEXT("Active Ripples: %d/%d\n")
            TEXT("Current Time: %.2f\n")
            TEXT("Wave Scale: %.2f | Speed: %.2f | Height: %.2f"),
            GetActiveRippleCount(), MaxRipples,
            CurrentTime,
            WaveScale, WaveSpeed, WaveHeight
        );

        GEngine->AddOnScreenDebugMessage(-1, 0.0f, FColor::Cyan, DebugText);
    }
}
