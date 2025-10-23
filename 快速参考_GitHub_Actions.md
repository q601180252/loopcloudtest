# GitHub Actions 快速参考

## 🚀 快速开始（5 分钟版）

如果你已经有配置经验，这里是快速步骤：

### 1️⃣ 准备 6 个 Secrets

```
TEAMID                  # Apple Developer Team ID
FASTLANE_ISSUER_ID      # App Store Connect API Issuer ID
FASTLANE_KEY_ID         # App Store Connect API Key ID
FASTLANE_KEY            # App Store Connect API Key 内容（.p8 文件）
GH_PAT                  # GitHub Personal Access Token (workflow scope)
MATCH_PASSWORD          # 你设置的密码
```

### 2️⃣ 配置 GitHub

1. Fork `LoopWorkspace` 仓库
2. Settings → Secrets and variables → Actions
3. 添加上述 6 个 secrets
4. Variables 标签 → 添加 `ENABLE_NUKE_CERTS` = `true`

### 3️⃣ 运行工作流（按顺序）

```
Actions → 1. Validate Secrets → Run workflow ✅
Actions → 2. Add Identifiers → Run workflow ✅
(手动配置 App Group 和 capabilities)
Actions → 3. Create Certificates → Run workflow ✅
(首次：在 App Store Connect 创建 Loop app)
Actions → 4. Build Loop → Run workflow ✅ (等待 20-30 分钟)
```

### 4️⃣ TestFlight

1. 在 iPhone 安装 TestFlight app
2. 在 App Store Connect 添加测试用户
3. 接受邀请，安装 Loop

---

## 📝 手动配置检查清单

### Apple Developer Portal 配置

访问：https://developer.apple.com/account/resources/identifiers/list

- [ ] 创建 App Group: `group.com.你的TEAMID.loopkit.LoopGroup`
- [ ] Loop → 配置 App Groups → 选择 Loop App Group
- [ ] Loop → 启用 Time Sensitive Notifications
- [ ] Loop Intent Extension → 配置 App Groups
- [ ] Loop Status Extension → 配置 App Groups
- [ ] Loop Widget Extension → 配置 App Groups

### App Store Connect 配置

访问：https://appstoreconnect.apple.com/apps

- [ ] 创建 Loop app（Bundle ID: com.你的TEAMID.loopkit.Loop）
- [ ] 添加测试用户到 TestFlight

---

## 🔄 常用操作

### 手动构建

```
Actions → 4. Build Loop → Run workflow
```

### 查看构建状态

```
Actions → 4. Build Loop → 点击最新的运行记录
```

### 重新创建证书

```
Actions → 3. Create Certificates → Run workflow
```

### 下载构建产物

```
Actions → 4. Build Loop → 点击运行记录 → Artifacts → build-artifacts
```

---

## ⏰ 自动构建时间表

| 时间 | 操作 | 说明 |
|------|------|------|
| 每周三 08:00 UTC | 检查更新 | 如有更新则自动构建 |
| 每月 1 号 06:00 UTC | 自动构建 | 无论是否有更新都构建 |
| 每次构建 | Keep-alive | 提交到 alive 分支 |

**UTC 时间转换**：
- UTC 08:00 = 北京时间 16:00
- UTC 06:00 = 北京时间 14:00

---

## 🛠️ 故障排除速查

| 问题 | 解决方案 |
|------|----------|
| Secrets 验证失败 | 检查 6 个 secrets 是否都已配置，注意不要有多余空格 |
| 找不到 Bundle ID | 先运行 "2. Add Identifiers" |
| 证书错误 | 运行 "3. Create Certificates" 重新创建 |
| 构建超时 | GitHub Actions 有时会慢，重新运行即可 |
| TestFlight 未出现 | 等待 10-15 分钟处理时间 |
| 90 天过期 | 手动运行 "4. Build Loop" 或等待自动构建 |

---

## 📱 TestFlight 快速链接

- **App Store Connect**: https://appstoreconnect.apple.com/apps
- **TestFlight 用户**: https://appstoreconnect.apple.com/access/users
- **构建历史**: https://appstoreconnect.apple.com/apps → 选择 Loop → TestFlight

---

## 🔗 有用的链接

- **Apple Developer Portal**: https://developer.apple.com/account/resources/certificates/list
- **App Store Connect API**: https://appstoreconnect.apple.com/access/integrations/api
- **GitHub Token 设置**: https://github.com/settings/tokens
- **Loop 官方文档**: https://loopkit.github.io/loopdocs/

---

## 💡 小贴士

1. **保存 Secrets**：将 6 个 secrets 保存在密码管理器中
2. **定期检查**：每月查看一次构建状态
3. **备份密码**：`MATCH_PASSWORD` 丢失后需要重新配置所有证书
4. **测试构建**：首次配置后，先用测试设备验证
5. **更新通知**：关注 Loop 官方更新公告

---

## 📊 工作流时间参考

| 工作流 | 平均耗时 | 说明 |
|--------|----------|------|
| 1. Validate Secrets | 1-2 分钟 | 验证配置 |
| 2. Add Identifiers | 1-2 分钟 | 创建 identifiers |
| 3. Create Certificates | 5-10 分钟 | 生成证书 |
| 4. Build Loop | 20-30 分钟 | 构建和上传 |

---

## ⚡ 紧急操作

### 立即构建新版本

```bash
Actions → 4. Build Loop → Run workflow → Run workflow
```

### 证书过期了

```bash
# 方法 1：自动续期（如果已启用 ENABLE_NUKE_CERTS）
Actions → 4. Build Loop → Run workflow

# 方法 2：手动重建
Actions → 3. Create Certificates → Run workflow
等待完成后
Actions → 4. Build Loop → Run workflow
```

### 重置所有证书

```bash
1. 删除 Match-Secrets 仓库
2. Actions → 3. Create Certificates → Run workflow
3. Actions → 4. Build Loop → Run workflow
```

---

**最后更新**：2025年10月23日

