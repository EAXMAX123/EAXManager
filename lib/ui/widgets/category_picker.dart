/// 书架分类选择弹窗
///
/// 勾选已有分类，也可以当场新建。长按分类可以改名或删除。
library;

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../source/comic_source.dart';
import '../../state/app_services.dart';

class CategoryPicker {
  CategoryPicker._();

  /// 弹出选择框。返回 null 表示取消，否则返回选中的分类 id 列表（可能是空的）
  static Future<List<int>?> show(
    BuildContext context, {
    required SourceId sid,
  }) => showDialog<List<int>>(
    context: context,
    builder: (_) => _CategoryPickerDialog(sid: sid),
  );
}

class _CategoryPickerDialog extends StatefulWidget {
  const _CategoryPickerDialog({required this.sid});

  final SourceId sid;

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  final TextEditingController _name = TextEditingController();

  List<ShelfCategory> _all = const [];
  final Set<int> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dao = AppServices.I.dao;
    final all = await dao.listCategories();
    final mine = await dao.categoryIdsOf(widget.sid);
    if (!mounted) return;
    setState(() {
      _all = all;
      _selected
        ..clear()
        ..addAll(mine);
      _loading = false;
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final id = await AppServices.I.dao.createCategory(name);
    if (id == 0) return;
    _name.clear();
    final all = await AppServices.I.dao.listCategories();
    if (!mounted) return;
    setState(() {
      _all = all;
      _selected.add(id);
    });
  }

  Future<void> _rename(ShelfCategory category) async {
    final controller = TextEditingController(text: category.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分类'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    await AppServices.I.dao.renameCategory(category.id, result);
    await _load();
  }

  Future<void> _delete(ShelfCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除分类「${category.name}」'),
        content: const Text('只会删掉这个分类，里面的本子还在书架上。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppServices.I.dao.deleteCategory(category.id);
    _selected.remove(category.id);
    await _load();
  }

  Future<void> _showActions(ShelfCategory category) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除分类'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') await _rename(category);
    if (action == 'delete') await _delete(category);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('加入书架'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _all.isEmpty ? '还没有分类，在下面建一个吧' : '勾选要放进去的分类（长按可改名或删除）',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final category in _all)
                          GestureDetector(
                            onLongPress: () => _showActions(category),
                            child: CheckboxListTile(
                              dense: true,
                              value: _selected.contains(category.id),
                              title: Text(category.name),
                              onChanged: (checked) => setState(() {
                                if (checked == true) {
                                  _selected.add(category.id);
                                } else {
                                  _selected.remove(category.id);
                                }
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _name,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '新建分类，比如「已看完」',
                            ),
                            onSubmitted: (_) => _create(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _create,
                          child: const Text('新建'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
