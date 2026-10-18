class ReadingProgressWriter {
  ReadingProgressWriter(this.persist, {required this.onError});

  final Future<void> Function(int page) persist;
  final void Function(Object error, StackTrace stack) onError;
  Future<void> _pending = Future.value();
  int? _lastQueued;

  Future<void> save(int page) {
    if (page < 1 || page == _lastQueued) return _pending;
    _lastQueued = page;
    _pending = _pending.then((_) async {
      try {
        await persist(page);
      } catch (error, stack) {
        if (_lastQueued == page) _lastQueued = null;
        onError(error, stack);
      }
    });
    return _pending;
  }
}
