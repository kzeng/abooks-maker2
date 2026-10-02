# Product Decisions

记录日期：2026-10-01

## 第一版范围

- 平台：Ubuntu 22.04 桌面端、Android 手机端。
- 输入：EPUB、TXT、PDF。
- PDF：第一版只处理可复制文本，不包含 OCR。
- TTS：使用 Edge TTS voices；需要联网，支持中文、英文及参考项目已有的粤语/繁体中文 voices。
- 输出：默认按章节生成 MP3，并支持合并为单个 MP3。
- 参数：支持 voice、语速、音调、输出目录和章节选择。
- Android：支持锁屏/切换应用后继续转换、取消、失败日志和章节级断点恢复。
- 构建：由 GitHub Actions 完成分析、测试、Android AAB 和 Ubuntu Linux release 构建。

## 暂不纳入

- MOBI、AZW/AZW3 等格式。
- 扫描 PDF OCR。
- 离线 TTS。
- 云端账号同步和服务器端书库。
- M4B 输出；保留为后续版本候选。

## 关键约束

Edge TTS 封装为独立的 `TtsProvider`，避免 UI 和转换流程依赖具体服务。书籍和生成音频默认只保存在用户设备；如果未来增加云端服务，必须重新评估隐私政策和 Play Console Data Safety 声明。

Android 文件访问使用系统文件选择器，不申请广泛存储权限。长时间转换使用 Android 前台媒体处理服务，并在服务停止、失败和完成时正确清理状态。

## 风险记录

1. Edge TTS 依赖网络及第三方服务行为，需显示网络错误并允许重试。
2. PDF 文本顺序和章节识别质量取决于文件排版，必须提供预览或日志。
3. Android 后台长任务受系统服务限制，需要真实设备验证。
4. Flutter SDK 和 Android SDK 已安装到当前用户目录；Linux 原生构建依赖仍需要管理员安装，ADB 无线真机连接待设备端口验证。

## CI/CD 决策

GitHub Actions 作为唯一的云端构建入口，建议拆分为：

- `ci.yml`：格式化检查、`flutter analyze`、单元测试。
- `build-android.yml`：生成签名或未签名 AAB，并保存构建产物。
- `build-linux.yml`：生成 Ubuntu Linux release bundle，并打包为后续可分发格式。
- `release.yml`：仅在 tag 或手动批准后发布 GitHub Release。

Android 签名文件、密码和 Play Console 凭据只能存放在 GitHub Actions Secrets/Environment 中，不得提交到仓库。真实手机调试仍在本地通过 USB 或无线 ADB 完成。
