/// 收藏夹：JM 和哔咔各一栏，两边能同时登录，都会自己重登
///
/// 两个源的收藏接口完全不一样（JM 有收藏夹分组，哔咔只有一个总列表），
/// 所以没硬凑成一套，各自一个子页面，外面只负责切换。
library;

import 'package:flutter/material.dart';

import '../../jm/jm_exception.dart';
import '../../jm/jm_models.dart';
import '../../source/comic_source.dart';
import '../../state/app_services.dart';
import '../widgets/album_cover.dart';
import 'detail_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String _source = 'jm';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _sourceBar(),
        Expanded(
          child: _source == 'jm'
              ? const _JmFavorites()
              : const _PicaFavorites(),
        ),
      ],
    );
  }

  Widget _sourceBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'jm',
            label: Text('JM'),
            icon: Icon(Icons.menu_book_outlined, size: 18),
          ),
          ButtonSegment(
            value: 'pica',
            label: Text('哔咔'),
            icon: Icon(Icons.photo_library_outlined, size: 18),
          ),
        ],
        selected: {_source},
        showSelectedIcon: false,
        onSelectionChanged: (value) =>
            setState(() => _source = value.first),
      ),
    );
  }
}

// ==================== JM ====================

class _JmFavorites extends StatefulWidget {
  const _JmFavorites();

  @override
  State<_JmFavorites> createState() => _JmFavoritesState();
}

class _JmFavoritesState extends State<_JmFavorites> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();

  bool _loggingIn = false;
  String? _loginError;

  List<JmSearchItem> _items = const [];
  List<JmFavoriteFolder> _folders = const [];
  String _folderId = '0';
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  String? _error;
  bool _sessionExpired = false;

  @override
  void initState() {
    super.initState();
    AppServices.I.account.addListener(_onAccountChanged);
    if (AppServices.I.account.value.isNotEmpty) _load();
  }

  @override
  void dispose() {
    AppServices.I.account.removeListener(_onAccountChanged);
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {
      _items = const [];
      _folders = const [];
      _error = null;
      _sessionExpired = false;
    });
    if (AppServices.I.account.value.isNotEmpty) _load();
  }

  Future<void> _doLogin() async {
    setState(() {
      _loggingIn = true;
      _loginError = null;
    });
    try {
      await AppServices.I.login(_user.text, _pass.text);
      if (!mounted) return;
      _pass.clear();
      setState(() => _loggingIn = false);
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loginError = e is JmException ? e.message : e.toString();
        _loggingIn = false;
      });
    }
  }

  Future<void> _logout() async {
    await AppServices.I.logout();
    if (!mounted) return;
    setState(() {
      _items = const [];
      _folders = const [];
      _sessionExpired = false;
    });
  }

  Future<void> _load({int page = 1, String? folderId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final targetFolder = folderId ?? _folderId;
    try {
      final result = await AppServices.I.client.favoriteFolder(
        page: page,
        folderId: targetFolder,
      );
      if (!mounted) return;
      setState(() {
        _items = page == 1 ? result.items : [..._items, ...result.items];
        _folders = result.folders;
        _folderId = targetFolder;
        _total = result.total;
        _page = page;
        _loading = false;
        _sessionExpired = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e is JmException && e.kind == JmErrorKind.unauthorized) {
          _sessionExpired = true;
          _error = '登录已失效，请重新登录';
        } else {
          _error = e is JmException ? e.friendlyMessage : e.toString();
        }
      });
    }
  }

  Future<void> _removeFavorite(JmSearchItem item) async {
    final confirmed = await _confirmRemove(context, item.name);
    if (confirmed != true || !mounted) return;

    try {
      await AppServices.I.client.setFavorite(item.id, want: false);
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != item.id).toList();
        _total = (_total - 1).clamp(0, _total);
      });
      _toast('已取消收藏');
    } on Exception catch (e) {
      if (!mounted) return;
      _toast(e is JmException ? e.message : '$e');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppServices.I.account,
      builder: (context, account, _) {
        if (account.isEmpty) return _buildLogin();
        return _buildFavorites(account);
      },
    );
  }

  Widget _buildLogin() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.favorite_border,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('登录 JM 账号后，这里会显示你收藏的本子', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            onSubmitted: (_) => _doLogin(),
            decoration: const InputDecoration(
              labelText: '密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loggingIn ? null : _doLogin,
            child: Text(_loggingIn ? '登录中…' : '登录'),
          ),
          if (_loginError != null) ...[
            const SizedBox(height: 12),
            Text(
              _loginError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '登录信息会留在本机，之后登录掉了会自动重登，不用每次手动输',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavorites(String account) {
    return Column(
      children: [
        _buildAccountBar(account),
        if (_folders.isNotEmpty) _buildFolderBar(),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildAccountBar(String account) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Icon(
            Icons.account_circle,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              account,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (_total > 0)
            Text(
              '共 $_total 本',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          TextButton(onPressed: _logout, child: const Text('退出')),
        ],
      ),
    );
  }

  Widget _buildFolderBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _folders
            .map(
              (f) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(f.name.isEmpty ? '收藏夹 ${f.id}' : f.name),
                  selected: _folderId == f.id,
                  onSelected: (_) => _load(page: 1, folderId: f.id),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _ErrorView(
        message: _error!,
        onRetry: _sessionExpired ? null : () => _load(),
        onLogout: _sessionExpired ? _logout : null,
      );
    }
    if (_items.isEmpty) {
      return const _EmptyView(text: '这个收藏夹还是空的');
    }

    return RefreshIndicator(
      onRefresh: () => _load(page: 1),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400 &&
              !_loading &&
              _items.length < _total) {
            _load(page: _page + 1);
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _items.length + (_loading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final item = _items[index];
            return ListTile(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DetailPage(sid: SourceId('jm', item.id), title: item.name),
                ),
              ),
              onLongPress: () => _removeFavorite(item),
              leading: AlbumCover(
                albumId: item.id,
                coverUrl: AppServices.I.client.coverUrl(item.id),
                show: AppServices.I.settings.value.showCoverInList,
              ),
              title: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: item.author.isEmpty
                  ? null
                  : Text(
                      item.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: IconButton(
                icon: const Icon(Icons.favorite, color: Colors.pinkAccent),
                tooltip: '取消收藏',
                onPressed: () => _removeFavorite(item),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==================== 哔咔 ====================

class _PicaFavorites extends StatefulWidget {
  const _PicaFavorites();

  @override
  State<_PicaFavorites> createState() => _PicaFavoritesState();
}

class _PicaFavoritesState extends State<_PicaFavorites> {
  final TextEditingController _mail = TextEditingController();
  final TextEditingController _pass = TextEditingController();

  bool _loggingIn = false;
  String? _loginError;

  List<ComicItem> _items = const [];
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  String? _error;
  bool _sessionExpired = false;

  @override
  void initState() {
    super.initState();
    AppServices.I.picaAccount.addListener(_onAccountChanged);
    if (AppServices.I.picaAccount.value.isNotEmpty) _load();
  }

  @override
  void dispose() {
    AppServices.I.picaAccount.removeListener(_onAccountChanged);
    _mail.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {
      _items = const [];
      _error = null;
      _sessionExpired = false;
    });
    if (AppServices.I.picaAccount.value.isNotEmpty) _load();
  }

  Future<void> _doLogin() async {
    setState(() {
      _loggingIn = true;
      _loginError = null;
    });
    try {
      await AppServices.I.picaLogin(_mail.text, _pass.text);
      if (!mounted) return;
      _pass.clear();
      setState(() => _loggingIn = false);
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loginError = e is SourceException ? e.message : e.toString();
        _loggingIn = false;
      });
    }
  }

  Future<void> _logout() async {
    await AppServices.I.picaLogout();
    if (!mounted) return;
    setState(() {
      _items = const [];
      _sessionExpired = false;
    });
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AppServices.I.pica.favorites(page: page);
      if (!mounted) return;
      setState(() {
        _items = page == 1 ? result.items : [..._items, ...result.items];
        _total = result.total;
        _page = page;
        _loading = false;
        _sessionExpired = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sessionExpired = e is SourceException && e.needsLogin;
        _error = e is SourceException ? e.message : e.toString();
      });
    }
  }

  Future<void> _removeFavorite(ComicItem item) async {
    final confirmed = await _confirmRemove(context, item.title);
    if (confirmed != true || !mounted) return;

    try {
      await AppServices.I.pica.setFavorite(item.sid.id, want: false);
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.sid.id != item.sid.id).toList();
        _total = (_total - 1).clamp(0, _total);
      });
      _toast('已取消收藏');
    } on Exception catch (e) {
      if (!mounted) return;
      _toast(e is SourceException ? e.message : '$e');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppServices.I.picaAccount,
      builder: (context, account, _) {
        if (account.isEmpty) return _buildLogin();
        return _buildFavorites(account);
      },
    );
  }

  Widget _buildLogin() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.favorite_border,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('登录哔咔账号后，这里会显示你收藏的本子', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          TextField(
            controller: _mail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱',
              hintText: '注册时填的邮箱，不是账号名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            onSubmitted: (_) => _doLogin(),
            decoration: const InputDecoration(
              labelText: '密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loggingIn ? null : _doLogin,
            child: Text(_loggingIn ? '登录中…' : '登录'),
          ),
          if (_loginError != null) ...[
            const SizedBox(height: 12),
            Text(
              _loginError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '登录信息会留在本机，之后 token 过期会自动重登',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavorites(String account) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Icon(
                Icons.account_circle,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  account,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (_total > 0)
                Text(
                  '共 $_total 本',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              TextButton(onPressed: _logout, child: const Text('退出')),
            ],
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _ErrorView(
        message: _error!,
        onRetry: _sessionExpired ? null : () => _load(),
        onLogout: _sessionExpired ? _logout : null,
      );
    }
    if (_items.isEmpty) {
      return const _EmptyView(text: '还没有收藏任何本子');
    }

    return RefreshIndicator(
      onRefresh: () => _load(page: 1),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400 &&
              !_loading &&
              _items.length < _total) {
            _load(page: _page + 1);
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _items.length + (_loading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final item = _items[index];
            return ListTile(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DetailPage(sid: item.sid, title: item.title),
                ),
              ),
              onLongPress: () => _removeFavorite(item),
              leading: AlbumCover(
                albumId: item.sid.id,
                coverUrl: item.coverUrl,
                httpHeaders: item.coverHeaders,
                show: AppServices.I.settings.value.showCoverInList,
              ),
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: item.subtitle.isEmpty
                  ? null
                  : Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: IconButton(
                icon: const Icon(Icons.favorite, color: Colors.pinkAccent),
                tooltip: '取消收藏',
                onPressed: () => _removeFavorite(item),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==================== 公用小组件 ====================

/// 取消收藏前的确认框
Future<bool?> _confirmRemove(BuildContext context, String title) =>
    showDialog<bool>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('取消收藏'),
    content: Text('把《$title》从收藏夹中移除？'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, true),
        child: const Text('移除'),
      ),
    ],
  ),
);

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.outline),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry, this.onLogout});

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (onRetry != null)
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            if (onLogout != null)
              TextButton(onPressed: onLogout, child: const Text('退出当前账号')),
          ],
        ),
      ),
    );
  }
}
