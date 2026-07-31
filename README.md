# LoopWorkspace

The Loop app can be built using GitHub in a browser on any computer or using a Mac with Xcode.

* Non-developers may prefer the GitHub method
* Developers or Loopers who want full build control may prefer the Mac/Xcode method

## 本仓库定制

本仓库在 LoopWorkspace 基础上增加了以下功能：

- `MicroTech LinX` CGM，新添加固定使用直接连接。
- Loop 首页通用血糖历史入口，任意已配置 CGM 均可查看最近 6、12、24 小时数据。
- LinX 完整连接日志和广播诊断日志。
- Nightscout、MicroTech 等 CGM 插件的完整真机构建和安装检查。

完整 App 构建、真机安装和发布必须使用 `LoopWorkspace` scheme。单独使用 `Loop` scheme 可能漏掉 Nightscout 等插件。

## 文档导航

| 文档 | 用途 |
|---|---|
| [AGENTS.md](AGENTS.md) | 开发、验证、提交和推送规则 |
| [PROGRESS.md](PROGRESS.md) | 当前状态和倒序进展记录 |
| [血糖历史页面设计](docs/superpowers/specs/2026-07-31-glucose-history-page-design.md) | 首页入口、6/12/24 小时页面、数据来源和验证边界 |
| [血糖历史实施计划](docs/superpowers/plans/2026-07-31-glucose-history-page.md) | 实现步骤、测试入口和实际执行状态 |
| [LinX 固定直连设计](docs/superpowers/specs/2026-07-31-linx-direct-only-setup-design.md) | 新添加页面、固定直连行为和保留范围 |
| [LinX 固定直连实施计划](docs/superpowers/plans/2026-07-31-linx-direct-only-setup.md) | 实现步骤、测试入口和发布检查 |
| [LinX 广播模式设计（历史记录）](docs/superpowers/specs/2026-07-31-linx-broadcast-mode-design.md) | 已取消的添加模式选择，仅保留历史设计和排障依据 |
| [工具与踩坑](docs/工具与踩坑.md) | Nightscout 完整插件安装、LinX 日志、真机和 TestFlight 排障 |

## GitHub Build Instructions

The GitHub Build Instructions are at this [link](fastlane/testflight.md) and further expanded in [LoopDocs: Browser Build](https://loopkit.github.io/loopdocs/gh-actions/gh-overview/).

## Mac/Xcode Build Instructions

The rest of this README contains information needed for Mac/Xcode build. Additonal instructions are found in [LoopDocs: Mac/Xcode Build](https://loopkit.github.io/loopdocs/build/overview/).

### Clone

This repository uses git submodules to pull in the various workspace dependencies.

To clone this repo:

```
git clone --branch=<branch> --recurse-submodules https://github.com/LoopKit/LoopWorkspace
```

Replace `<branch>` with the initial LoopWorkspace repository branch you wish to checkout.

### Open

Change to the cloned directory and open the workspace in Xcode:

```
cd LoopWorkspace
xed .
```

### Input your development team

You should be able to build to a simulator without changing anything. But if you wish to build to a real device, you'll need a developer account, and you'll need to tell Xcode about your team id, which you can find at https://developer.apple.com/.

Select the LoopConfigOverride file in Xcode's project navigator, uncomment the `LOOP_DEVELOPMENT_TEAM`, and replace the existing team id with your own id.

### Build

Select the "LoopWorkspace" scheme (not the "Loop" scheme) when building or running the complete app. For component tests, use the specific test scheme documented in the relevant implementation plan.
