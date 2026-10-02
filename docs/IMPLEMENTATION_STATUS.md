# Implementation Status

本文件记录第一版实现范围，避免界面已经出现但功能尚未完成时造成误解。

## 已完成

- Flutter Material 3 应用骨架，支持 Ubuntu/Linux 与 Android 构建。
- 系统文件选择器，支持 EPUB、TXT、PDF；Android 使用系统 SAF，桌面使用原生文件选择器。
- EPUB 解析：读取 OPF manifest/spine，按阅读顺序提取 HTML 正文和章节标题。
- EPUB 清理：跳过明显目录、版权/前置目录和短广告推广页，正文从首个章节标题开始。
- TXT 解析：UTF-8/BOM 清理和空白规范化。
- PDF 解析：使用 PDFium 提取文本；扫描版 PDF 会提示暂不支持 OCR。
- Edge TTS 章节生成：`zh-CN-YunjianNeural`、语速、音调、网络异常由 provider 处理，输出本地 MP3。
- 章节转换使用有上限的并发队列，默认最多同时请求 2 个章节；设置页可调整为 1–10 个章节。遇到疑似限流时会降低并发并重试当前章节；输出和合并仍保持原章节顺序。
- 设置已持久化：声音、语速、音调和输出目录会保存到本机配置。
- 转换任务支持进度显示、取消、失败状态和重新转换；同时生成章节 MP3 与合并 MP3。
- 已生成音频可使用 `just_audio` 按章节连续播放。
- 解析单元测试、真实结构 EPUB 回归测试、Material 3 widget 测试、Flutter analyze/test，以及 Ubuntu release 构建。

## 尚待完成

- Android 前台服务：当前转换任务在 Flutter 页面进程中执行，尚未实现进程被系统回收后的续作、通知和断点恢复。
- 音频合并目前采用 MP3 字节串接，主流播放器通常可播放，但尚未加入重新编码/封面和章节元数据。
- Android release 签名、隐私政策页面、Data safety 声明和 Play 内测材料仍需发布前配置。

## 运行检查

```bash
source scripts/dev-env.sh
flutter analyze
flutter test
flutter build linux --release
flutter build appbundle --release
```

拿到真实 EPUB 后可运行：

```bash
dart run tool/validate_epub.dart "/path/to/罗马人的故事.epub"
dart run tool/test_tts.dart
```

Edge TTS 需要网络连接；应用不会把整本书上传到项目服务器，但文本会发送到 Microsoft Edge TTS 服务以生成音频。
