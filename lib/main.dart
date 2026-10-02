import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pdfrx/pdfrx.dart';

import 'core/models/book_document.dart';
import 'core/parsers/book_parser.dart';
import 'core/services/app_settings.dart';
import 'core/services/android_foreground_service.dart';
import 'core/services/edge_tts_service.dart';
import 'core/services/file_location_service.dart';
import 'core/services/task_store.dart';

Future<void> main() async {
  pdfrxFlutterInitialize();
  runApp(const ABooksMakerApp());
}

class ABooksMakerApp extends StatelessWidget {
  const ABooksMakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xff6750a4));
    return MaterialApp(
      title: 'Abooks Maker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: scheme),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _parser = BookParser();
  final _tts = EdgeTtsService();
  final _player = AudioPlayer();
  final _settingsRepository = SettingsRepository();
  final _taskStore = TaskStore();
  AppSettings _settings = const AppSettings();
  final List<ConversionJob> _jobs = [];
  final Set<String> _cancelledJobIds = <String>{};
  final Set<String> _pausedJobIds = <String>{};
  Future<void> _conversionQueue = Future<void>.value();
  Future<void> _persistQueue = Future<void>.value();
  Timer? _backgroundCommandTimer;
  String? _activeJobId;
  int _selectedIndex = 0;
  bool _importing = false;
  String? _playingJobTitle;
  Process? _desktopAudioProcess;
  bool _desktopAudioPaused = false;
  late final StreamSubscription<PlayerState> _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
    _backgroundCommandTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollBackgroundCommand(),
    );
    _playerStateSubscription = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _backgroundCommandTimer?.cancel();
    _desktopAudioProcess?.kill();
    _player.dispose();
    _playerStateSubscription.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await AndroidForegroundService.requestNotificationPermission();
    final settings = await _settingsRepository.load();
    final storedJobs = await _taskStore.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _jobs.addAll(
        storedJobs.map(ConversionJob.fromJson).whereType<ConversionJob>(),
      );
    });
    for (final job in List<ConversionJob>.from(_jobs)) {
      if (job.status == JobStatus.running || job.status == JobStatus.paused) {
        _enqueueConversion(job, resume: true);
      }
    }
  }

  Future<void> _persistJobs() async {
    final snapshot = _jobs.map((job) => job.toJson()).toList();
    _persistQueue = _persistQueue.then((_) => _taskStore.save(snapshot));
    await _persistQueue;
  }

  Future<void> _pollBackgroundCommand() async {
    final command = await AndroidForegroundService.command();
    final activeId = _activeJobId;
    if (activeId == null || command == null) return;
    if (command == 'pause') {
      _pausedJobIds.add(activeId);
      await AndroidForegroundService.clearCommand();
      final index = _jobs.indexWhere((job) => job.id == activeId);
      if (index >= 0) {
        _jobs[index] = _jobs[index].copyWith(status: JobStatus.paused);
      }
      await _persistJobs();
      if (mounted) setState(() {});
    } else if (command == 'resume') {
      _pausedJobIds.remove(activeId);
      await AndroidForegroundService.clearCommand();
      final index = _jobs.indexWhere((job) => job.id == activeId);
      if (index >= 0) {
        _jobs[index] = _jobs[index].copyWith(status: JobStatus.running);
      }
      await _persistJobs();
      if (mounted) setState(() {});
    } else if (command == 'cancel') {
      _cancelledJobIds.add(activeId);
      await AndroidForegroundService.clearCommand();
    }
  }

  void _enqueueConversion(ConversionJob job, {bool resume = false}) {
    _conversionQueue = _conversionQueue.then((_) async {
      await _convertJob(job, resume: resume);
    });
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.transform_outlined),
        selectedIcon: Icon(Icons.transform),
        label: '转换',
      ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '设置',
      ),
      const NavigationDestination(
        icon: Icon(Icons.info_outline),
        selectedIcon: Icon(Icons.info),
        label: '关于',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final body = switch (_selectedIndex) {
          0 => LibraryView(
            jobs: _jobs,
            importing: _importing,
            onImport: _importBook,
            onConvert: _enqueueConversion,
            onTogglePlayback: _togglePlayback,
            onCancel: _cancelJob,
            onTogglePause: _toggleConversionPause,
            onDelete: _deleteJob,
            onOpenFolder: _openJobFolder,
            currentPlaybackTitle: _playingJobTitle,
            isPlaying:
                _player.playing ||
                (_desktopAudioProcess != null && !_desktopAudioPaused),
          ),
          1 => SettingsView(
            settings: _settings,
            onChanged: _saveSettings,
            onPreview: _previewSettings,
          ),
          _ => const AboutView(),
        };
        return Scaffold(
          appBar: AppBar(title: const Text('Abooks Maker')),
          body: compact
              ? body
              : Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: (value) =>
                          setState(() => _selectedIndex = value),
                      labelType: NavigationRailLabelType.all,
                      destinations: destinations
                          .map(
                            (item) => NavigationRailDestination(
                              icon: item.icon,
                              selectedIcon: item.selectedIcon,
                              label: Text(item.label),
                            ),
                          )
                          .toList(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                ),
          bottomNavigationBar: compact
              ? NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (value) =>
                      setState(() => _selectedIndex = value),
                  destinations: destinations,
                )
              : null,
        );
      },
    );
  }

  Future<void> _importBook() async {
    if (_importing) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'txt', 'pdf'],
    );
    if (result.isEmpty || !mounted) return;

    setState(() => _importing = true);
    var imported = 0;
    for (final file in result) {
      try {
        final bytes = await _readFileBytes(file);
        final document = await _parser.parse(fileName: file.name, bytes: bytes);
        if (!mounted) return;
        setState(() {
          _jobs.insert(
            0,
            ConversionJob(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              title: document.title,
              format: document.format.label,
              status: JobStatus.ready,
              detail:
                  '${document.chapters.length} 个章节 · ${document.characterCount} 字 · 等待 Edge TTS',
              document: document,
            ),
          );
        });
        await _persistJobs();
        imported++;
      } on Object catch (error) {
        if (mounted) _showMessage('${file.name}：${_friendlyError(error)}');
      }
    }
    if (mounted) {
      setState(() => _importing = false);
      if (imported > 0) _showMessage('已导入 $imported 个文件，可开始配置转换。');
    }
  }

  Future<Uint8List> _readFileBytes(PlatformFile file) async {
    return file.readAsBytes();
  }

  Future<void> _convertJob(ConversionJob job, {bool resume = false}) async {
    final index = _jobs.indexOf(job);
    if (index < 0 || job.document == null) return;
    _activeJobId = job.id;
    _cancelledJobIds.remove(job.id);
    if (!resume) _pausedJobIds.remove(job.id);
    setState(
      () => _jobs[index] = job.copyWith(
        status: JobStatus.running,
        detail: '正在连接 Edge TTS…',
        progress: 0.01,
      ),
    );
    await _persistJobs();
    await AndroidForegroundService.start(
      title: job.title,
      total: job.document!.chapters.length,
    );
    var lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    var lastNotificationUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final result = await _tts.convert(
        job.document!,
        settings: _settings.tts,
        maxConcurrent: _settings.concurrentTasks,
        outputDirectory: _settings.outputDirectory == null
            ? null
            : '${_settings.outputDirectory}/${_safeFileName(job.title)}',
        onProgress: (progress) {
          if (!mounted || index >= _jobs.length) return;
          final now = DateTime.now();
          final chapterCompleted = progress.completedFile != null;
          final updateUi =
              chapterCompleted ||
              now.difference(lastUiUpdate) >= const Duration(milliseconds: 250);
          final updateNotification =
              chapterCompleted ||
              now.difference(lastNotificationUpdate) >=
                  const Duration(milliseconds: 500);
          if (!updateUi && !updateNotification) return;
          final files = [..._jobs[index].audioFiles];
          if (chapterCompleted &&
              !files.contains(progress.completedFile!.path)) {
            files.add(progress.completedFile!.path);
          }
          if (updateUi) {
            lastUiUpdate = now;
            setState(
              () => _jobs[index] = _jobs[index].copyWith(
                status: _pausedJobIds.contains(job.id)
                    ? JobStatus.paused
                    : JobStatus.running,
                progress: progress.fraction.clamp(0.01, 1.0),
                audioFiles: files,
                detail:
                    '${progress.chapter}/${progress.totalChapters} · ${progress.message}',
              ),
            );
          }
          if (chapterCompleted) unawaited(_persistJobs());
          if (updateNotification) {
            lastNotificationUpdate = now;
            unawaited(
              AndroidForegroundService.update(
                completed: (progress.fraction * progress.totalChapters).round(),
                total: progress.totalChapters,
                message: progress.message,
              ),
            );
          }
        },
        isCancelled: () => _cancelledJobIds.contains(job.id),
        isPaused: () => _pausedJobIds.contains(job.id),
        resumeExisting: resume,
      );
      if (!mounted || index >= _jobs.length) return;
      setState(
        () => _jobs[index] = _jobs[index].copyWith(
          status: JobStatus.completed,
          detail: '已生成 ${result.chapters.length} 个章节 MP3 和合并文件',
          progress: 1,
          audioFiles: result.chapters.map((file) => file.path).toList(),
          mergedAudioFile: result.mergedFile.path,
        ),
      );
      await _persistJobs();
      await AndroidForegroundService.stop();
      _showMessage('转换完成，章节 MP3 和合并 MP3 已保存。');
    } on ConversionCancelled {
      if (!mounted || index >= _jobs.length) return;
      setState(
        () => _jobs[index] = _jobs[index].copyWith(
          status: JobStatus.cancelled,
          detail: '已取消，可重新开始',
        ),
      );
      await _persistJobs();
      await AndroidForegroundService.stop();
    } on Object catch (error) {
      if (!mounted || index >= _jobs.length) return;
      setState(
        () => _jobs[index] = _jobs[index].copyWith(
          status: JobStatus.failed,
          detail: _friendlyError(error),
        ),
      );
      await _persistJobs();
      await AndroidForegroundService.stop();
      _showMessage('转换失败：${_friendlyError(error)}');
    } finally {
      if (_activeJobId == job.id) _activeJobId = null;
    }
  }

  void _cancelJob(ConversionJob job) {
    _cancelledJobIds.add(job.id);
    unawaited(AndroidForegroundService.cancel());
    _showMessage('将在当前章节完成后停止转换。');
  }

  Future<void> _deleteJob(ConversionJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务记录？'),
        content: Text('将从任务列表中删除“${job.title}”。已生成的音频文件不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除记录'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_playingJobTitle == job.title) await _stopPlayback();
    setState(() => _jobs.removeWhere((item) => item.id == job.id));
    await _persistJobs();
  }

  Future<void> _openJobFolder(ConversionJob job) async {
    final audioPath =
        job.mergedAudioFile ??
        (job.audioFiles.isEmpty ? null : job.audioFiles.first);
    if (audioPath == null) return;
    try {
      await FileLocationService.openDirectory(File(audioPath).parent.path);
    } on Object catch (error) {
      _showMessage('打开文件夹失败：${_friendlyError(error)}');
    }
  }

  void _toggleConversionPause(ConversionJob job) {
    final index = _jobs.indexOf(job);
    if (_pausedJobIds.contains(job.id)) {
      _pausedJobIds.remove(job.id);
      unawaited(AndroidForegroundService.resume());
      _showMessage('已继续转换。');
      if (index >= 0) {
        _jobs[index] = _jobs[index].copyWith(status: JobStatus.running);
      }
    } else {
      _pausedJobIds.add(job.id);
      unawaited(AndroidForegroundService.pause());
      _showMessage('已暂停转换，可在通知栏继续。');
      if (index >= 0) {
        _jobs[index] = _jobs[index].copyWith(status: JobStatus.paused);
      }
    }
    unawaited(_persistJobs());
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    await _settingsRepository.save(settings);
  }

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_').trim();

  Future<void> _togglePlayback(ConversionJob job) async {
    if (job.audioFiles.isEmpty) return;
    try {
      if (Platform.isLinux) {
        final file = job.mergedAudioFile ?? job.audioFiles.first;
        if (_playingJobTitle == job.title && _desktopAudioProcess != null) {
          _desktopAudioProcess!.stdin.write('p');
          await _desktopAudioProcess!.stdin.flush();
          _desktopAudioPaused = !_desktopAudioPaused;
          if (mounted) setState(() {});
          return;
        }
        await _playDesktopAudio(file, job.title);
        return;
      }
      if (_playingJobTitle == job.title) {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
        return;
      }
      await _player.setAudioSources(
        job.audioFiles.map((path) => AudioSource.file(path)).toList(),
      );
      _playingJobTitle = job.title;
      await _player.play();
      _showMessage('正在播放：${job.title}（共 ${job.audioFiles.length} 章）');
    } on Object catch (error) {
      _showMessage('播放失败：${_friendlyError(error)}');
    }
  }

  Future<void> _stopPlayback() async {
    if (Platform.isLinux) {
      _desktopAudioProcess?.kill();
      _desktopAudioProcess = null;
      if (mounted) setState(() => _playingJobTitle = null);
      return;
    }
    await _player.stop();
    if (mounted) setState(() => _playingJobTitle = null);
  }

  Future<void> _previewSettings() async {
    _showMessage('正在生成试听音频…');
    try {
      final file = await _tts.preview(settings: _settings.tts);
      if (Platform.isLinux) {
        await _playDesktopAudio(file.path, '试听');
        _showMessage('正在播放当前设置的试听效果。');
        return;
      }
      await _player.setFilePath(file.path);
      _playingJobTitle = '试听';
      await _player.play();
      _showMessage('正在播放当前设置的试听效果。');
    } on Object catch (error) {
      _showMessage('试听失败：${_friendlyError(error)}');
    }
  }

  Future<void> _playDesktopAudio(String path, String title) async {
    _desktopAudioProcess?.kill();
    final process = await Process.start('ffplay', [
      '-nodisp',
      '-autoexit',
      '-loglevel',
      'error',
      path,
    ], runInShell: false);
    _desktopAudioProcess = process;
    _desktopAudioPaused = false;
    _playingJobTitle = title;
    if (mounted) setState(() {});
    process.exitCode.then((_) {
      if (identical(_desktopAudioProcess, process)) {
        _desktopAudioProcess = null;
        if (mounted) setState(() => _playingJobTitle = null);
      }
    });
  }

  String _friendlyError(Object error) =>
      error is FormatException ? error.message : '读取失败，请确认文件未损坏且格式受支持';

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.jobs,
    required this.importing,
    required this.onImport,
    required this.onConvert,
    required this.onTogglePlayback,
    required this.onCancel,
    required this.onTogglePause,
    required this.onDelete,
    required this.onOpenFolder,
    required this.currentPlaybackTitle,
    required this.isPlaying,
  });

  final List<ConversionJob> jobs;
  final bool importing;
  final VoidCallback onImport;
  final ValueChanged<ConversionJob> onConvert;
  final ValueChanged<ConversionJob> onTogglePlayback;
  final ValueChanged<ConversionJob> onCancel;
  final ValueChanged<ConversionJob> onTogglePause;
  final ValueChanged<ConversionJob> onDelete;
  final ValueChanged<ConversionJob> onOpenFolder;
  final String? currentPlaybackTitle;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      children: [
        Text('有声书工具', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        Card(
          child: InkWell(
            onTap: importing ? null : onImport,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(
                    importing ? Icons.hourglass_top : Icons.menu_book,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text('导入电子书', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('支持 EPUB、TXT、可复制文本 PDF，可一次选择多个文件'),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: importing ? null : onImport,
                    icon: importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(importing ? '正在读取' : '选择文件'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('转换任务', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (jobs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('暂无转换任务。导入电子书后，任务会显示在这里。'),
          )
        else
          ...jobs.map(
            (job) => JobCard(
              job: job,
              onConvert: onConvert,
              onTogglePlayback: onTogglePlayback,
              isCurrentPlayback: currentPlaybackTitle == job.title,
              isPlaying: isPlaying,
              onCancel: onCancel,
              onTogglePause: onTogglePause,
              onDelete: onDelete,
              onOpenFolder: onOpenFolder,
            ),
          ),
      ],
    );
  }
}

class WaveProgressIndicator extends StatefulWidget {
  const WaveProgressIndicator({super.key, required this.progress});

  final double progress;

  @override
  State<WaveProgressIndicator> createState() => _WaveProgressIndicatorState();
}

class _WaveProgressIndicatorState extends State<WaveProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => SizedBox(
        height: 12,
        child: CustomPaint(
          painter: _WaveProgressPainter(
            progress: widget.progress,
            phase: _controller.value,
            background: colors.surfaceContainerHighest,
            foreground: const Color(0xff2e7d32),
          ),
        ),
      ),
    );
  }
}

class _WaveProgressPainter extends CustomPainter {
  const _WaveProgressPainter({
    required this.progress,
    required this.phase,
    required this.background,
    required this.foreground,
  });

  final double progress;
  final double phase;
  final Color background;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas.drawRRect(bounds, Paint()..color = background);
    canvas.save();
    canvas.clipRRect(bounds);
    final indeterminate = progress < 0.02;
    final rawStart = indeterminate ? (phase * 1.4 - 0.4) * size.width : 0.0;
    final width = indeterminate ? size.width * 0.45 : size.width * progress;
    final start = rawStart.clamp(0.0, size.width);
    final end = (rawStart + width).clamp(0.0, size.width);
    if (end > 0 && (indeterminate || progress > 0)) {
      final path = Path()..moveTo(start, size.height);
      for (var x = start; x <= end; x += 2) {
        final wave =
            size.height *
            0.18 *
            math.sin((x / size.width * 2 * math.pi * 2) + phase * 2 * math.pi);
        path.lineTo(x, size.height / 2 + wave);
      }
      path
        ..lineTo(end, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = foreground
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaveProgressPainter oldDelegate) => true;
}

class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.onConvert,
    required this.onTogglePlayback,
    required this.isCurrentPlayback,
    required this.isPlaying,
    required this.onCancel,
    required this.onTogglePause,
    required this.onDelete,
    required this.onOpenFolder,
  });

  final ConversionJob job;
  final ValueChanged<ConversionJob> onConvert;
  final ValueChanged<ConversionJob> onTogglePlayback;
  final bool isCurrentPlayback;
  final bool isPlaying;
  final ValueChanged<ConversionJob> onCancel;
  final ValueChanged<ConversionJob> onTogglePause;
  final ValueChanged<ConversionJob> onDelete;
  final ValueChanged<ConversionJob> onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final percentage = (job.progress.clamp(0.0, 1.0) * 100).round();
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: job.status == JobStatus.running
                ? null
                : CircleAvatar(child: Icon(job.status.icon)),
            title: Text(_taskTitle(job.title)),
            subtitle: job.status == JobStatus.running
                ? null
                : Text('${job.format} · ${job.detail}'),
            trailing:
                job.document != null &&
                    (job.status == JobStatus.ready ||
                        job.status == JobStatus.cancelled)
                ? OutlinedButton(
                    onPressed: () => onConvert(job),
                    child: const Text('转换'),
                  )
                : job.status == JobStatus.running ||
                      job.status == JobStatus.paused
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: job.status == JobStatus.paused
                            ? '继续转换'
                            : '暂停转换',
                        onPressed: () => onTogglePause(job),
                        icon: Icon(
                          job.status == JobStatus.paused
                              ? Icons.play_arrow
                              : Icons.pause,
                        ),
                      ),
                      IconButton(
                        tooltip: '取消转换',
                        onPressed: () => onCancel(job),
                        icon: const Icon(Icons.stop_circle_outlined),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          if (job.status == JobStatus.completed && job.audioFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: isCurrentPlayback && isPlaying ? '暂停' : '播放/继续',
                    onPressed: () => onTogglePlayback(job),
                    icon: Icon(
                      isCurrentPlayback && isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: '删除任务记录',
                    onPressed: () => onDelete(job),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  IconButton(
                    tooltip: '打开音频文件夹',
                    onPressed: () => onOpenFolder(job),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ],
              ),
            ),
          if (job.status == JobStatus.running)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: WaveProgressIndicator(progress: job.progress),
                  ),
                  const SizedBox(width: 12),
                  Text('$percentage%'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _taskTitle(String title) {
  final characters = title.runes.toList();
  if (characters.length <= 25) return title;
  return '${String.fromCharCodes(characters.take(25))}...';
}

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onPreview,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;
  final VoidCallback onPreview;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  static const voices = <String, String>{
    'zh-CN-YunjianNeural': '云健（男）',
    'zh-CN-YunxiNeural': '云希（男）',
    'zh-CN-YunxiaNeural': '云夏（男）',
    'zh-CN-YunyangNeural': '云扬（男）',
    'zh-CN-liaoning-XiaobeiNeural': '晓北（女·东北）',
    'zh-HK-HiuGaaiNeural': '晓佳（女·粤语）',
    'zh-HK-HiuMaanNeural': '晓曼（女·粤语）',
    'zh-TW-HsiaoChenNeural': '晓臻（女·台湾）',
    'zh-TW-HsiaoYuNeural': '晓雨（女·台湾）',
    'zh-TW-YunJheNeural': '云哲（男·台湾）',
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('转换设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        ListTile(
          leading: Icon(Icons.record_voice_over),
          title: Text('Edge TTS voice'),
          subtitle: Text(
            '${widget.settings.voice} · ${voices[widget.settings.voice] ?? '自定义'}',
          ),
          trailing: Icon(Icons.chevron_right),
          onTap: _chooseVoice,
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.layers_outlined),
          title: Text('同时转换章节数'),
          subtitle: Text('${widget.settings.concurrentTasks} 个章节'),
          trailing: Icon(Icons.chevron_right),
          onTap: () => _chooseNumber(
            '同时转换章节数',
            widget.settings.concurrentTasks,
            1,
            10,
            (value) {
              widget.onChanged(
                widget.settings.copyWith(concurrentTasks: value),
              );
            },
          ),
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.speed),
          title: Text('语速'),
          subtitle: Text(_signed(widget.settings.ratePercent, '%')),
          trailing: Icon(Icons.chevron_right),
          onTap: () => _chooseNumber(
            '语速',
            widget.settings.ratePercent,
            -50,
            100,
            (value) {
              widget.onChanged(widget.settings.copyWith(ratePercent: value));
            },
          ),
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.tune),
          title: Text('音调'),
          subtitle: Text(_signed(widget.settings.pitchHz, 'Hz')),
          trailing: Icon(Icons.chevron_right),
          onTap: () =>
              _chooseNumber('音调', widget.settings.pitchHz, -20, 20, (value) {
                widget.onChanged(widget.settings.copyWith(pitchHz: value));
              }),
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.folder_outlined),
          title: Text('输出格式'),
          subtitle: Text(
            widget.settings.outputDirectory ?? '系统下载目录 · abooks · 章节 MP3',
          ),
          trailing: Icon(Icons.chevron_right),
          onTap: _chooseOutputDirectory,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: widget.onPreview,
          icon: const Icon(Icons.volume_up),
          label: const Text('试听当前设置'),
        ),
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Edge TTS 需要网络连接。'),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseOutputDirectory() async {
    final directory = await FilePicker.getDirectoryPath();
    if (directory != null) {
      widget.onChanged(widget.settings.copyWith(outputDirectory: directory));
    }
  }

  Future<void> _chooseVoice() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择 Edge TTS 声音'),
        children: voices.entries
            .map(
              (entry) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text('${entry.value}\n${entry.key}'),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null) {
      widget.onChanged(widget.settings.copyWith(voice: selected));
    }
  }

  Future<void> _chooseNumber(
    String title,
    int current,
    int min,
    int max,
    ValueChanged<int> onSave,
  ) async {
    var value = current.toDouble();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_displayNumber(value.round(), title)),
              Slider(
                value: value,
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
                label: value.round().toString(),
                onChanged: (next) => setDialogState(() => value = next),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == true) onSave(value.round());
  }

  String _signed(int value, String suffix) =>
      '${value >= 0 ? '+' : ''}$value$suffix';

  String _displayNumber(int value, String title) => switch (title) {
    '语速' => _signed(value, '%'),
    '音调' => _signed(value, 'Hz'),
    _ => '$value 个',
  };
}

enum JobStatus { ready, running, paused, completed, failed, cancelled }

extension on JobStatus {
  IconData get icon => switch (this) {
    JobStatus.ready => Icons.pending_outlined,
    JobStatus.running => Icons.sync,
    JobStatus.paused => Icons.pause_circle_outline,
    JobStatus.completed => Icons.check_circle_outline,
    JobStatus.failed => Icons.error_outline,
    JobStatus.cancelled => Icons.cancel_outlined,
  };
}

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: scheme.primaryContainer,
                        child: Icon(
                          Icons.headphones_rounded,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Abooks Maker',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'a ebooks audio convert tool.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.person_outline),
                    title: Text('Author'),
                    subtitle: Text('zengkai001@gmail.com'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.info_outline),
                    title: Text('Version'),
                    subtitle: Text('1.0.2'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ConversionJob {
  const ConversionJob({
    required this.id,
    required this.title,
    required this.format,
    required this.status,
    required this.detail,
    this.document,
    this.audioFiles = const [],
    this.mergedAudioFile,
    this.progress = 0,
  });

  final String id;
  final String title;
  final String format;
  final JobStatus status;
  final String detail;
  final BookDocument? document;
  final List<String> audioFiles;
  final String? mergedAudioFile;
  final double progress;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'format': format,
    'status': status.name,
    'detail': detail,
    'progress': progress,
    'audioFiles': audioFiles,
    'mergedAudioFile': mergedAudioFile,
    if (document != null)
      'document': {
        'title': document!.title,
        'format': document!.format.name,
        'chapters': document!.chapters
            .map((chapter) => {'title': chapter.title, 'text': chapter.text})
            .toList(),
      },
  };

  static ConversionJob? fromJson(Map<String, dynamic> json) {
    try {
      final documentJson = json['document'] as Map?;
      BookDocument? document;
      if (documentJson != null) {
        final chapters = (documentJson['chapters'] as List)
            .whereType<Map>()
            .map(
              (chapter) => BookChapter(
                title: chapter['title'] as String,
                text: chapter['text'] as String,
              ),
            )
            .toList();
        final recoveredChapters = chapters.length == 1
            ? BookParser.splitLongChapterText(chapters.first.text)
            : const <BookChapter>[];
        final sourceChapters = recoveredChapters.length >= 2
            ? recoveredChapters
            : chapters;
        final cleanedChapters = sourceChapters.length > 1
            ? sourceChapters.where((chapter) {
                final lowerTitle = chapter.title.toLowerCase();
                final chapterSignals = RegExp(
                  r'第\s*(?:\d+|[一二三四五六七八九十百千万]+)\s*章',
                ).allMatches(chapter.text).length;
                final looksLikeContents =
                    chapterSignals >= 8 &&
                    (lowerTitle.contains('版权') ||
                        lowerTitle.contains('目录') ||
                        chapter.text.length > 15000);
                return !looksLikeContents;
              }).toList()
            : chapters;
        document = BookDocument(
          title: documentJson['title'] as String,
          format: BookFormat.values.byName(documentJson['format'] as String),
          chapters: cleanedChapters.isEmpty ? sourceChapters : cleanedChapters,
        );
      }
      final statusName = json['status'] as String? ?? JobStatus.ready.name;
      final status = JobStatus.values.byName(statusName);
      return ConversionJob(
        id:
            json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title: json['title'] as String,
        format: json['format'] as String,
        status: status == JobStatus.running ? JobStatus.running : status,
        detail: json['detail'] as String? ?? '等待转换',
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        audioFiles:
            (json['audioFiles'] as List?)?.whereType<String>().toList() ??
            const [],
        mergedAudioFile: json['mergedAudioFile'] as String?,
        document: document,
      );
    } on Object {
      return null;
    }
  }

  ConversionJob copyWith({
    String? detail,
    JobStatus? status,
    List<String>? audioFiles,
    String? mergedAudioFile,
    double? progress,
  }) => ConversionJob(
    id: id,
    title: title,
    format: format,
    status: status ?? this.status,
    detail: detail ?? this.detail,
    document: document,
    audioFiles: audioFiles ?? this.audioFiles,
    mergedAudioFile: mergedAudioFile ?? this.mergedAudioFile,
    progress: progress ?? this.progress,
  );
}
