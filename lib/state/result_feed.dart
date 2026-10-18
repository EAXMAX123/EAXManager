class ResultFeed<T> {
  List<T> items = [];
  bool loading = false;
  bool initialized = false;
  String? error;
  int page = 1;
  int total = 0;
  int _revision = 0;

  int begin({bool reset = false}) {
    loading = true;
    initialized = true;
    error = null;
    if (reset) {
      items = [];
      total = 0;
      page = 1;
    }
    return ++_revision;
  }

  bool accepts(int revision) => revision == _revision;

  bool complete(
    int revision,
    List<T> next, {
    required int page,
    required int total,
  }) {
    if (!accepts(revision)) return false;
    items = page == 1 ? List.of(next) : [...items, ...next];
    this.page = page;
    this.total = next.isEmpty ? items.length : total;
    loading = false;
    error = null;
    return true;
  }

  bool fail(int revision, String message) {
    if (!accepts(revision)) return false;
    error = message;
    loading = false;
    return true;
  }
}
