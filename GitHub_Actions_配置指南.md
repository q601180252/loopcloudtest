# GitHub Actions 自动编译 IPA 配置指南

## 📋 概述

本项目已配置完整的 GitHub Actions 工作流，可以在不使用 Mac 的情况下，通过浏览器自动编译 Loop 应用并上传到 TestFlight。

## ✨ 功能特性

- ✅ 自动构建 IPA 文件
- ✅ 自动上传到 TestFlight
- ✅ 每周自动检查更新并构建
- ✅ 每月自动构建（确保 TestFlight 90 天有效期）
- ✅ 自动更新和续期证书
- ✅ Keep-alive 机制（防止 GitHub Actions 被禁用）

## 🎯 前置要求

1. **GitHub 账号**（免费版即可）
2. **付费 Apple Developer 账号**（$99/年）
3. **时间**：首次配置约需 2-3 小时

## 📝 配置步骤

### 第一步：生成 Apple 密钥（4个 Secrets）

#### 1.1 获取 TEAMID

1. 访问 [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list)
2. 登录后，右上角可以看到 **Team ID**
3. 复制并保存为 `TEAMID`

#### 1.2 创建 App Store Connect API Key

1. 访问 [App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
2. 点击 "Integrations" 标签
3. 点击 "+" 创建新密钥
4. 配置：
   - **Name**: FastLane API Key
   - **Access**: Admin
5. 点击 "Generate"
6. 保存以下信息：
   - **Issuer ID** → 保存为 `FASTLANE_ISSUER_ID`
   - **Key ID** → 保存为 `FASTLANE_KEY_ID`
   - **下载 .p8 文件**，用文本编辑器打开，复制全部内容（包括 BEGIN 和 END 行）→ 保存为 `FASTLANE_KEY`

#### 1.3 记录格式示例

```
TEAMID=ABC1234567
FASTLANE_ISSUER_ID=12345678-1234-1234-1234-123456789012
FASTLANE_KEY_ID=ABCD123456
FASTLANE_KEY=-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg...
(省略中间内容)
...xyzABC==
-----END PRIVATE KEY-----
```

### 第二步：生成 GitHub 密钥（2个 Secrets）

#### 2.1 创建 GitHub Personal Access Token (GH_PAT)

1. 访问 [GitHub Token 设置](https://github.com/settings/tokens/new)
2. 配置：
   - **Note**: FastLane Access Token
   - **Expiration**: No expiration（不过期）
   - **Select scopes**: 勾选 `workflow`（会自动勾选 `repo`）
3. 点击 "Generate token"
4. **立即复制** token（只显示一次）→ 保存为 `GH_PAT`

#### 2.2 创建 MATCH_PASSWORD

这是你自己设定的密码，用于加密证书存储：

```
MATCH_PASSWORD=你设置的密码（请记住！）
```

**⚠️ 重要**：如果丢失 `MATCH_PASSWORD`，需要删除 Match-Secrets 仓库并重新创建。

### 第三步：Fork 项目

1. 访问你的 LoopWorkspace fork（或创建 fork）
2. 确保仓库名称为 `LoopWorkspace`（不要重命名）

### 第四步：配置 GitHub Secrets

#### 方式一：在组织级别配置（推荐，如果有多个项目）

1. 进入你的 GitHub 组织页面
2. Settings → Secrets and variables → Actions
3. 点击 "Secrets" 标签
4. 添加以下 6 个 secrets（点击 "New organization secret"）：

#### 方式二：在仓库级别配置

1. 进入你的 `LoopWorkspace` 仓库
2. Settings → Secrets and variables → Actions
3. 点击 "Secrets" 标签
4. 添加以下 6 个 secrets（点击 "New repository secret"）：

| Secret 名称 | 说明 | 示例 |
|------------|------|------|
| `TEAMID` | Apple 开发者团队 ID | ABC1234567 |
| `FASTLANE_ISSUER_ID` | App Store Connect API Issuer ID | 12345678-1234... |
| `FASTLANE_KEY_ID` | App Store Connect API Key ID | ABCD123456 |
| `FASTLANE_KEY` | App Store Connect API Key 内容 | -----BEGIN PRIVATE KEY----- ... |
| `GH_PAT` | GitHub Personal Access Token | ghp_xxxxxxxxxxxx |
| `MATCH_PASSWORD` | 你设置的证书加密密码 | 你的密码 |

### 第五步：配置 Variables

1. 在同一页面，点击 "Variables" 标签
2. 添加以下变量（点击 "New repository variable" 或 "New organization variable"）：

| Variable 名称 | 值 | 说明 |
|--------------|-----|------|
| `ENABLE_NUKE_CERTS` | true | 允许自动更新过期证书 |

### 第六步：运行工作流

#### 6.1 启用 GitHub Actions

1. 进入仓库的 **Actions** 标签
2. 如果提示需要启用，点击 "I understand my workflows, go ahead and enable them"

#### 6.2 运行工作流（按顺序）

##### ① 验证 Secrets

1. 左侧选择 **"1. Validate Secrets"**
2. 右侧点击 **"Run workflow"** → **"Run workflow"**
3. 等待 1-2 分钟，确认显示 ✅ 绿色对勾

##### ② 添加 Identifiers

1. 左侧选择 **"2. Add Identifiers"**
2. 右侧点击 **"Run workflow"** → **"Run workflow"**
3. 等待完成

##### ③ 手动配置 Apple Developer Portal

**⚠️ 这一步必须手动完成！**

###### 创建 App Group（如果不存在）

1. 访问 [Register an App Group](https://developer.apple.com/account/resources/identifiers/applicationGroup/add/)
2. 配置：
   - **Description**: Loop App Group
   - **Identifier**: `group.com.你的TEAMID.loopkit.LoopGroup`
   - 将 `你的TEAMID` 替换为你的实际 Team ID
3. 点击 "Continue" → "Register"

###### 配置 Bundle Identifiers

1. 访问 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
2. 对以下 4 个 Identifier，逐个进行配置：
   - **Loop**
   - **Loop Intent Extension**
   - **Loop Status Extension**
   - **Loop Widget Extension**

对每个 Identifier：
1. 点击 Identifier 名称
2. 找到 "App Groups" capability
3. 点击 "Configure"
4. 勾选你创建的 "Loop App Group"
5. 点击 "Continue" → "Save" → "Confirm"

###### 添加 Time Sensitive Notifications（仅 Loop）

1. 在 [Identifiers 列表](https://developer.apple.com/account/resources/identifiers/list)中，点击 **Loop**
2. 向下滚动找到 **"Time Sensitive Notifications"**
3. 确保左侧的 Enable 复选框被勾选
4. 如果做了修改，点击 "Save"

##### ④ 创建证书

1. 左侧选择 **"3. Create Certificates"**
2. 右侧点击 **"Run workflow"** → **"Run workflow"**
3. 等待完成（约 5-10 分钟）
4. 证书会自动存储在 `Match-Secrets` 私有仓库中

##### ⑤ 创建 Loop App（首次需要）

**如果你从未创建过 Loop app，需要这一步：**

1. 访问 [App Store Connect Apps](https://appstoreconnect.apple.com/apps)
2. 点击蓝色 "+" 图标 → "New App"
3. 配置：
   - **Platform**: iOS
   - **Name**: 任意唯一名称（如 "My Loop App"）
   - **Primary Language**: 你的语言
   - **Bundle ID**: 选择 `com.你的TEAMID.loopkit.Loop`
   - **SKU**: 任意（如 "123"）
   - **User Access**: Full Access
4. 点击 "Create"

**不需要填写后续表单**，那是用于提交到 App Store 的。

##### ⑥ 构建 Loop

1. 左侧选择 **"4. Build Loop"**
2. 右侧点击 **"Run workflow"** → **"Run workflow"**
3. ☕ 休息一下，构建需要 **20-30 分钟**
4. 完成后，app 会出现在 [App Store Connect](https://appstoreconnect.apple.com/apps)

### 第七步：TestFlight 测试

#### 7.1 添加测试用户

1. 访问 [App Store Connect - Users and Access](https://appstoreconnect.apple.com/access/users)
2. 添加测试用户
3. 将他们加入 TestFlight Internal Testing 组

#### 7.2 在 iPhone 上安装

1. 在 iPhone 上安装 **TestFlight** app
2. 使用测试用户的 Apple ID 登录
3. 接受邀请，安装 Loop

## 🤖 自动构建说明

### 默认行为

配置完成后，GitHub Actions 会自动：

- **每周三 08:00 UTC**：检查更新，如有更新则自动构建
- **每月 1 号 06:00 UTC**：自动构建（无论是否有更新）
- **Keep-alive**：定期提交到 `alive` 分支，防止 Actions 被禁用

### 自定义自动构建

如果想修改自动构建行为，可以添加以下 Variables：

| Variable | 值 | 效果 |
|----------|-----|------|
| `SCHEDULED_SYNC` | false | 禁用自动更新检查 |
| `SCHEDULED_BUILD` | false | 仅在有更新时构建 |

#### 组合效果

| SCHEDULED_SYNC | SCHEDULED_BUILD | 自动行为 |
|----------------|-----------------|----------|
| true（或不设置）| true（或不设置）| 每周检查更新并构建，每月自动构建 |
| true（或不设置）| false | 每周检查更新，仅在有更新时构建 |
| false | true（或不设置）| 每月自动构建，不自动更新 |
| false | false | 完全禁用自动构建 |

## 📁 文件结构

```
.github/
└── workflows/
    ├── 1_validate_secrets.yml     # 验证 secrets 配置
    ├── 2_add_identifiers.yml      # 添加 app identifiers
    ├── 3_create_certificates.yml  # 创建和管理证书
    └── 4_build_loop.yml           # 构建并上传到 TestFlight
```

## 🔧 故障排除

### Secrets 验证失败

- 检查所有 6 个 secrets 是否正确配置
- 确保 `FASTLANE_KEY` 包含完整内容（包括 BEGIN 和 END 行）
- 确保没有多余的空格或换行

### 证书创建失败

- 确保 Apple Developer 账号是付费的
- 检查 API Key 权限是否为 "Admin"
- 确保 `GH_PAT` 有 `workflow` 权限

### 构建失败

- 检查是否完成了所有手动配置步骤
- 确保 App Group 已正确配置
- 查看 Actions 日志中的详细错误信息

### 证书过期

- 证书会在到期 30 天前收到邮件通知
- 如果启用了 `ENABLE_NUKE_CERTS`，会自动续期
- 也可以手动运行 "3. Create Certificates" workflow

### 构建频率问题

- TestFlight 版本有效期为 90 天
- 确保至少每 90 天构建一次
- 使用自动构建可以避免过期

## 📊 工作流说明

### 1. Validate Secrets

- **用途**：验证所有 6 个 secrets 配置正确
- **运行时机**：手动运行
- **耗时**：1-2 分钟

### 2. Add Identifiers

- **用途**：在 Apple Developer Portal 创建 app identifiers
- **运行时机**：手动运行（首次配置）
- **耗时**：1-2 分钟
- **注意**：运行后需要手动配置 App Group

### 3. Create Certificates

- **用途**：创建签名证书和 provisioning profiles
- **运行时机**：手动运行 / 证书过期时自动运行
- **耗时**：5-10 分钟
- **存储**：证书加密存储在 `Match-Secrets` 仓库

### 4. Build Loop

- **用途**：构建 IPA 并上传到 TestFlight
- **运行时机**：
  - 手动运行
  - 每周三 08:00 UTC（如有更新）
  - 每月 1 号 06:00 UTC（总是构建）
- **耗时**：20-30 分钟
- **产物**：
  - IPA 文件
  - 构建日志
  - 上传到 TestFlight

### Keep Alive 机制

- **用途**：防止 GitHub Actions 因 60 天无活动而被禁用
- **运行时机**：随 Build Loop 自动运行
- **行为**：在 `alive` 分支创建 dummy commit

## 🔐 安全说明

- 所有 secrets 都加密存储在 GitHub
- 证书使用 `MATCH_PASSWORD` 加密存储
- `Match-Secrets` 是私有仓库，只有你能访问
- GitHub Actions 日志不会显示 secrets 值

## 📚 相关文档

- [Loop 官方文档](https://loopkit.github.io/loopdocs/)
- [浏览器构建概述](https://loopkit.github.io/loopdocs/browser/bb-overview/)
- [浏览器构建错误处理](https://loopkit.github.io/loopdocs/browser/bb-errors/)
- [TestFlight 使用指南](https://loopkit.github.io/loopdocs/browser/tf-users)

## ⚠️ 重要提示

1. **证书安全**：不要泄露你的 secrets 和 `MATCH_PASSWORD`
2. **90 天限制**：TestFlight 版本 90 天后过期，需要重新构建
3. **医疗设备**：Loop 是医疗设备软件，使用前请充分测试并咨询医疗专业人员
4. **备份**：请备份你的 secrets，特别是 `MATCH_PASSWORD`

## 🎉 完成！

配置完成后，你就可以：

- ✅ 在任何地方通过浏览器构建 Loop
- ✅ 自动获取更新并构建
- ✅ 通过 TestFlight 分发给测试用户
- ✅ 无需 Mac 和 Xcode

---

**配置完成时间**：2025年10月23日  
**支持的 Loop 版本**：LoopWorkspace (所有版本)  
**GitHub Actions**：4 个工作流

