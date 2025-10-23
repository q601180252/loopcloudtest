# 自定义 Bundle ID 配置说明

## ✅ 已完成的修改

你的项目使用自定义的 Bundle ID：**`com.HHZN32E89C.loopkit3.Loop`**

我已经将 Fastfile 和工作流文件中的所有 `loopkit` 修改为 `loopkit3`。

### 修改的文件：
- ✅ `fastlane/Fastfile` - 所有 bundle ID 引用已更新
- ✅ `.github/workflows/2_add_identifiers.yml` - App Group 提示已更新

## 📋 你的 Bundle ID 配置

### 主应用和扩展：

| 组件 | Bundle ID |
|------|-----------|
| Loop 主应用 | `com.HHZN32E89C.loopkit3.Loop` |
| Loop Status Extension | `com.HHZN32E89C.loopkit3.Loop.statuswidget` |
| Loop Watch | `com.HHZN32E89C.loopkit3.Loop.LoopWatch` |
| Loop Watch Extension | `com.HHZN32E89C.loopkit3.Loop.LoopWatch.watchkitextension` |
| Loop Intent Extension | `com.HHZN32E89C.loopkit3.Loop.Loop-Intent-Extension` |
| Loop Widget Extension | `com.HHZN32E89C.loopkit3.Loop.LoopWidgetExtension` |

### App Group：

- **Identifier**: `group.com.HHZN32E89C.loopkit3.LoopGroup`

## ⚠️ 重要：在 App Store Connect 中创建 App

你需要在 App Store Connect 中创建 Loop app：

### 步骤：

1. **访问 App Store Connect**：
   ```
   https://appstoreconnect.apple.com/apps
   ```

2. **点击蓝色 "+" 图标** → **"New App"**

3. **填写信息**：
   - **Platform**: iOS
   - **Name**: 任意唯一名称（如 "My Loop" 或 "Loop LiYang"）
   - **Primary Language**: Chinese (Simplified) - 中文（简体）
   - **Bundle ID**: 选择 **`com.HHZN32E89C.loopkit3.Loop`**
     - ⚠️ 确保选择的是 `loopkit3` 而不是 `loopkit`
   - **SKU**: 任意（如 "123"）
   - **User Access**: Full Access

4. **点击 "Create"**

5. **完成！** - 不需要填写后续的截图、描述等信息

## 🔍 验证 Bundle ID 是否存在

在创建 App 之前，先确认你的 Bundle ID 已在 Apple Developer Portal 中创建：

1. 访问：https://developer.apple.com/account/resources/identifiers/list
2. 确认存在以下 6 个 identifiers：
   - `com.HHZN32E89C.loopkit3.Loop`
   - `com.HHZN32E89C.loopkit3.Loop.statuswidget`
   - `com.HHZN32E89C.loopkit3.Loop.LoopWatch`
   - `com.HHZN32E89C.loopkit3.Loop.LoopWatch.watchkitextension`
   - `com.HHZN32E89C.loopkit3.Loop.Loop-Intent-Extension`
   - `com.HHZN32E89C.loopkit3.Loop.LoopWidgetExtension`

如果这些 Bundle ID 不存在，需要先运行 **"2. Add Identifiers"** 工作流。

## 🚀 下一步操作

### 1. 提交代码更改

```bash
git add fastlane/Fastfile .github/workflows/
git commit -m "Update bundle IDs to loopkit3"
git push
```

### 2. 在 App Store Connect 创建 App

按照上面的步骤创建 app（使用 `com.HHZN32E89C.loopkit3.Loop`）

### 3. 重新运行构建

1. 访问：https://github.com/你的用户名/loopcloudtest/actions
2. 选择 **"4. Build Loop"**
3. 点击 **"Run workflow"** → **"Run workflow"**
4. 等待约 20-30 分钟

## 💡 注意事项

### App Group 配置

如果之前创建过 App Group，确保使用的是：
- **`group.com.HHZN32E89C.loopkit3.LoopGroup`**

如果用的是旧的 `group.com.HHZN32E89C.loopkit.LoopGroup`，需要：
1. 创建新的 App Group：`group.com.HHZN32E89C.loopkit3.LoopGroup`
2. 在所有 Bundle Identifiers 中配置新的 App Group

### 证书和 Provisioning Profiles

如果之前创建过证书，可能需要重新创建以匹配新的 Bundle ID：

```
Actions → 3. Create Certificates → Run workflow
```

## 📊 常见问题

### Q: 为什么要用 loopkit3 而不是 loopkit？

A: 可能是因为：
- 之前已经有 `loopkit` 的配置
- 区分不同版本的 Loop
- 个人偏好或组织要求

### Q: 可以改回 loopkit 吗？

A: 可以，但需要：
1. 修改 Fastfile 将 `loopkit3` 改回 `loopkit`
2. 在 Apple Developer Portal 创建新的 identifiers
3. 重新创建证书
4. 在 App Store Connect 创建新的 app

### Q: 已经有 loopkit 的 app，可以共存吗？

A: 可以！`loopkit` 和 `loopkit3` 是完全独立的 Bundle ID，可以同时存在。

## ✅ 修改完成清单

- [x] Fastfile 更新为 loopkit3
- [x] GitHub Actions 工作流更新
- [ ] 在 App Store Connect 创建 app
- [ ] 重新运行构建工作流
- [ ] 通过 TestFlight 测试

---

**修改日期**：2025年10月23日  
**Team ID**：HHZN32E89C  
**Bundle ID 前缀**：loopkit3

