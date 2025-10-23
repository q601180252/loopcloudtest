# Apple iOS 18 SDK 强制要求说明

## ⚠️ Apple 新政策（2025年生效）

**从 2025 年开始，Apple 强制要求所有上传到 App Store Connect 的应用必须使用 iOS 18 SDK（Xcode 16）构建。**

## ❌ 遇到的错误

```
ERROR: Validation failed (409) 
SDK version issue. This app was built with the iOS 17.5 SDK. 
All iOS and iPadOS apps must be built with the iOS 18 SDK or later, 
included in Xcode 16 or later, in order to be uploaded to App Store Connect 
or submitted for distribution.
```

## 🔍 问题原因

1. **GitHub Actions macos-14 runner**
   - 只有 Xcode 15.4
   - 使用 iOS 17.5 SDK
   - 不满足 Apple 的新要求

2. **Apple 的新政策**
   - 2025 年强制实施
   - 必须使用 iOS 18 SDK
   - 必须使用 Xcode 16 或更高版本

3. **IPA 构建成功但上传失败**
   - 本地编译正常
   - 证书签名正常
   - 但被 App Store Connect 拒绝

## ✅ 解决方案：升级到 macos-15 Runner

### 实施的修改

升级所有 GitHub Actions 工作流：

```yaml
# 之前
runs-on: macos-14

# 之后
runs-on: macos-15
```

### 为什么选择 macos-15

| Runner | Xcode 版本 | iOS SDK | 状态 |
|--------|-----------|---------|------|
| macos-13 | Xcode 14.x | iOS 16.x | ⛔ 过时 |
| macos-14 | Xcode 15.4 | iOS 17.5 | ❌ 不满足要求 |
| macos-15 | Xcode 16.x | iOS 18.x | ✅ 满足要求 |

### 改进的 Xcode 选择逻辑

```yaml
- name: Select Xcode Version
  run: |
    # 列出所有可用的 Xcode 版本
    ls -1 /Applications/ | grep Xcode
    
    # 优先选择 Xcode 16
    if [ -d "/Applications/Xcode_16.1.app" ]; then
      sudo xcode-select -switch /Applications/Xcode_16.1.app/Contents/Developer
    elif [ -d "/Applications/Xcode_16.0.app" ]; then
      sudo xcode-select -switch /Applications/Xcode_16.0.app/Contents/Developer
    fi
    
    # 显示选择的版本
    xcodebuild -version
```

## 📋 修改的文件

所有 4 个工作流文件都已升级到 macos-15：

- ✅ `.github/workflows/1_validate_secrets.yml`
- ✅ `.github/workflows/2_add_identifiers.yml`
- ✅ `.github/workflows/3_create_certificates.yml`
- ✅ `.github/workflows/4_build_loop.yml`

## 🎯 预期结果

使用 macos-15 runner 后：

### 构建环境

```
✅ macOS 15 (Sequoia)
✅ Xcode 16.0 或更高版本
✅ iOS 18 SDK
✅ Swift 6
```

### 编译结果

```
✅ 原生支持 @retroactive
✅ 满足 Apple SDK 要求
✅ Archive 成功
✅ Export IPA 成功
✅ 上传到 App Store Connect 成功 ✨
✅ 出现在 TestFlight ✨
```

## 💡 额外好处

升级到 Xcode 16 后：

1. **不再需要移除 @retroactive**
   - 原生支持 Swift 6 特性
   - 但我们保留了这个步骤作为保险

2. **更好的性能**
   - Xcode 16 构建速度更快
   - 更好的优化

3. **面向未来**
   - 符合 Apple 最新要求
   - 支持最新的 iOS 特性

## ⚠️ 注意事项

### macos-15 Runner 状态

- macos-15 可能是较新的 runner
- 如果遇到问题，可能需要等待 GitHub 稳定版本
- 可以查看 [GitHub Actions Runner Images](https://github.com/actions/runner-images)

### 构建时间

- macos-15 可能比 macos-14 略慢（初期）
- 但满足 Apple 要求是必须的

### 替代方案

如果 macos-15 不可用：

1. **等待 GitHub 更新 macos-14**
   - GitHub 可能会更新 macos-14 到 Xcode 16

2. **使用 Self-hosted Runner**
   - 在自己的 Mac 上运行
   - 完全控制 Xcode 版本

3. **使用其他 CI 服务**
   - Bitrise
   - CircleCI
   - Codemagic

## 📊 GitHub Actions Runner 对照表

| Runner | macOS 版本 | 默认 Xcode | 状态 |
|--------|-----------|------------|------|
| macos-13 | Ventura 13 | Xcode 14.3.1 | 已弃用 |
| macos-14 | Sonoma 14 | Xcode 15.4 | ❌ SDK 过旧 |
| macos-15 | Sequoia 15 | Xcode 16.x | ✅ 推荐 |

## 🔗 相关链接

- **Apple SDK 要求公告**: https://developer.apple.com/news/
- **GitHub Actions Runners**: https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners
- **Xcode 16 发布说明**: https://developer.apple.com/xcode/

## 📝 完整的修复时间线

```
问题 1: NotificationHelperOverride.swift 缺失
  → ✅ 在构建前自动创建

问题 2: @retroactive 不支持（Xcode 15.4）
  → ✅ 自动移除（临时方案）

问题 3: WatchApp Bundle ID 不匹配
  → ✅ 替换 Info.plist 中的变量

问题 4: iOS 17.5 SDK 被拒绝（Apple 新政策）
  → ✅ 升级到 macos-15 runner（Xcode 16）
```

## 🎯 最终配置

```yaml
# GitHub Actions 工作流配置
runs-on: macos-15            # macOS Sequoia
Xcode: 16.x                  # 自动选择最新的 Xcode 16
Swift: 6.x                   # 原生支持所有 Swift 6 特性
iOS SDK: 18.x                # 满足 Apple 要求
```

---

**修复完成时间**：2025年10月23日  
**总共解决的问题**：4 个  
**最终方案**：macos-15 + Xcode 16

