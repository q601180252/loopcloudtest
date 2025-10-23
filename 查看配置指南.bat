@echo off
chcp 65001 >nul
echo ==========================================
echo GitHub Actions 配置指南
echo ==========================================
echo.
echo 注意：iOS 应用的构建必须在 macOS 或 GitHub Actions（云端）上进行
echo 但是 GitHub Actions 的配置可以在任何平台的浏览器中完成
echo.
echo ==========================================
echo 文档文件
echo ==========================================
echo.
echo 1. GitHub_Actions_配置指南.md - 完整配置步骤（推荐从这里开始）
echo 2. 快速参考_GitHub_Actions.md - 快速参考手册
echo 3. 初始化说明.md - 项目初始化说明
echo.
echo ==========================================
echo 在 Windows 上的操作步骤
echo ==========================================
echo.
echo 第一步：Fork 项目到你的 GitHub 账号
echo   访问：https://github.com/LoopKit/LoopWorkspace
echo   点击右上角的 "Fork" 按钮
echo.
echo 第二步：配置 GitHub Secrets
echo   访问：https://github.com/你的用户名/LoopWorkspace/settings/secrets/actions
echo   添加 6 个必需的 secrets（详见配置指南）
echo.
echo 第三步：运行 GitHub Actions 工作流
echo   访问：https://github.com/你的用户名/LoopWorkspace/actions
echo   按顺序运行 4 个工作流
echo.
echo 第四步：在 iPhone 上通过 TestFlight 安装
echo   在 iPhone 上安装 TestFlight app
echo   接受邀请并安装 Loop
echo.
echo ==========================================
echo 打开文档
echo ==========================================
echo.
choice /C 123 /M "选择要查看的文档（1/2/3）"
if errorlevel 3 goto doc3
if errorlevel 2 goto doc2
if errorlevel 1 goto doc1

:doc1
echo.
echo 正在打开 GitHub Actions 配置指南...
start GitHub_Actions_配置指南.md
goto end

:doc2
echo.
echo 正在打开快速参考手册...
start 快速参考_GitHub_Actions.md
goto end

:doc3
echo.
echo 正在打开初始化说明...
start 初始化说明.md
goto end

:end
echo.
echo ==========================================
echo 有用的链接
echo ==========================================
echo.
echo Apple Developer Portal:
echo https://developer.apple.com/account/resources/certificates/list
echo.
echo App Store Connect:
echo https://appstoreconnect.apple.com/apps
echo.
echo GitHub Token 设置:
echo https://github.com/settings/tokens
echo.
echo Loop 官方文档:
echo https://loopkit.github.io/loopdocs/
echo.
pause

