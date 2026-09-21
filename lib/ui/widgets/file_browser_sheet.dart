/// 简易文件浏览器：用于选择背景图或下载目录，无需额外权限依赖
library;

import 'dart:io';

import 'package:flutter/material.dart';

class FileBrowserSheet extends StatefulWidget {
  const FileBrowserSheet({
    super.key,
    required this.title,
    this.startPath,
    this.extensions = const [],
    this.pickDirectory = false,
  });

  final String title;
  final String? startPath;

  /// 允许选中的文件后缀（小写，含点），为空表示只列目录
  final List<String> extensions;

  /// true 时只能选择文件夹
  final bool pickDirectory;

  /// 打开选择器，返回选中的路径；用户取消时返回 null
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? startPath,
    List<String> extensions = const [],
    bool pickDirectory = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: FileBrowserSheet(
          title: title,
          startPath: startPath,
          extensions: extensions,
          pickDirectory: pickDirectory,
        ),
      ),
    );
  }

  @override
  State<FileBrowserSheet> createState() => _FileBrowserSheetState();
}

class _FileBrowserSheetState extends State<FileBrowserSheet> {
  static const List<String> _roots = ['/storage/emulated/0', '/sdcard'];

  late String _path;
  List<Directory> _dirs = const [];
  List<File> _files = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.startPath?.trim() ?? '';
    if (_path.isEmpty || !Directory(_path).existsSync()) {
      _path = _roots.firstWhere(
        (p) => Directory(p).existsSync(),
        orElse: () => Directory.current.path,
      );
    }
    _list();
  }

  Future<void> _list() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dir = Directory(_path);
      final dirs = <Directory>[];
      final files = <File>[];

      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.path.split('/').last;
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          dirs.add(entity);
        } else if (entity is File && _matches(entity.path)) {
          files.add(entity);
        }
      }

      dirs.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      files.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _files = files;
        _loading = false;
      });
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '无法读取该目录：${e.message}';
        _dirs = const [];
        _files = const [];
        _loading = false;
      });
    }
  }

  bool _matches(String path) {
    if (widget.extensions.isEmpty) return false;
    final lower = path.toLowerCase();
    return widget.extensions.any(lower.endsWith);
  }

  void _enter(String path) {
    _path = path;
    _list();
  }

  void _goUp() {
    if (_path == '/' || _path.isEmpty) return;
    final parent = _path.substring(0, _path.lastIndexOf('/'));
    _enter(parent.isEmpty ? '/' : parent);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canGoUp = _path != '/' && _path.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (widget.pickDirectory)
                FilledButton(
                  onPressed: () => Navigator.pop(context, _path),
                  child: const Text('选择此文件夹'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                tooltip: '上一级',
                onPressed: canGoUp ? _goUp : null,
              ),
              Expanded(
                child: Text(
                  _path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _list,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_dirs.isEmpty && _files.isEmpty) {
      return Center(
        child: Text(
          '这里没有可选项',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    return ListView.builder(
      itemCount: _dirs.length + _files.length,
      itemBuilder: (context, index) {
        if (index < _dirs.length) {
          final dir = _dirs[index];
          return ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(
              dir.path.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _enter(dir.path),
          );
        }

        final file = _files[index - _dirs.length];
        return ListTile(
          leading: const Icon(Icons.image_outlined),
          title: Text(
            file.path.split('/').last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.pop(context, file.path),
        );
      },
    );
  }
}
