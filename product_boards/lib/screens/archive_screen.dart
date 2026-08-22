      _snack('Не удалось добавить ссылку: $error');
      return false;
    }
  }

  Future<bool> _confirmDuplicate(List<ArchiveItem> duplicates) async {
    final names = duplicates.map((item) => _categoryName(item.categoryId)).join('\n• ');
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Эта ссылка уже есть'),
            content: Text('• $names\n\nСоздать новый независимый объект?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить копию')),
            ],
          ),
        ) ?? false;
  }

  String _categoryName(String? id) {
    if (id == null) return 'Неразобранное';
    for (final category in _categories) {
      if (category.id == id) return '«${category.name}»';
    }
    return 'Подборка';
  }

  Future<void> _openDetail(ArchiveItem item) async {
    final result = await Navigator.push<ArchiveItem>(context, MaterialPageRoute(builder: (_) => ArchiveItemPage(repository: widget.repository, queue: widget.queue, item: item, categories: _categories)));
    if (!mounted) return;
    if (result != null) unawaited(widget.queue.enqueue(result));
    await _reload();
  }

  Future<void> _openSmartSort() async {
    final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SmartSortPage(repository: widget.repository, items: _items)));
    if (result == true && mounted) await _reload();
  }

  Future<void> _addDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить ссылку'),
        content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'Вставьте ссылку...')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Добавить'))],
      ),