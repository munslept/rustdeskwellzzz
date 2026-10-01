import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart';
import '../../models/local_book_data.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';

const _storageKey = 'local-address-book-v1';

class LocalAddressBook extends StatefulWidget {
  const LocalAddressBook({Key? key}) : super(key: key);

  @override
  State<LocalAddressBook> createState() => _LocalAddressBookState();
}

class _LocalAddressBookState extends State<LocalAddressBook> {
  LocalBookData _data = LocalBookData();
  List<Peer> _recent = [];
  bool _loading = true;
  bool _busy = false;
  bool _storageBroken = false;
  String _error = '';
  String _query = '';
  String _view = 'all';
  String? _folder;
  String? _tag;
  String _sort = 'recent';

  String _text(String ru, String en) =>
      Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = bind.getLocalFlutterOption(k: _storageKey);
      final data = raw.isEmpty ? LocalBookData() : LocalBookData.decode(raw);
      if (!mounted) return;
      setState(() { _data = data; _storageBroken = false; _error = ''; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _storageBroken = true; _error = e.toString(); });
    }
    await _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final raw = await bind.mainLoadRecentPeersForAb(filter: '[]');
      final decoded = raw.isEmpty ? <dynamic>[] : jsonDecode(raw) as List;
      final recent = decoded.map((p) => Peer.fromJson(p as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() { _recent = recent; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<bool> _save(LocalBookData data, {bool restoring = false}) async {
    if (_busy) return false;
    if (_storageBroken && !restoring) {
      setState(() => _error = _text('Сначала восстановите книгу через импорт JSON.',
          'Restore the book with JSON import first.'));
      return false;
    }
    setState(() => _busy = true);
    try {
      final encoded = data.encode();
      LocalBookData.decode(encoded);
      await bind.setLocalFlutterOption(k: _storageKey, v: encoded);
      if (!mounted) return false;
      setState(() {
        _data = data; _storageBroken = false; _error = '';
        if (_folder != null && _folder!.isNotEmpty && !data.folders.contains(_folder)) {
          _folder = null;
        }
        if (_tag != null && !data.entries.values.any((e) => e.tags.contains(_tag))) {
          _tag = null;
        }
      });
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  LocalBookEntry _entry(Peer peer) => _data.entries[peer.id] ??
      LocalBookEntry(id: peer.id, alias: peer.alias);

  List<Peer> _peers() {
    final peers = {for (final p in _recent) p.id: p};
    for (final e in _data.entries.values.where((e) => e.saved)) {
      peers.putIfAbsent(e.id, () => Peer.fromJson({'id': e.id, 'alias': e.alias}));
    }
    final recentIds = {for (final p in _recent) p.id};
    final query = _query.toLowerCase();
    final filtered = peers.values.where((p) {
      final e = _entry(p);
      return (_view != 'saved' || e.saved) &&
          (_view != 'recent' || recentIds.contains(p.id)) &&
          (_folder == null || e.folder == _folder) &&
          (_tag == null || e.tags.contains(_tag)) &&
          [p.id, e.alias, p.hostname, p.username, e.note, ...e.tags]
              .join(' ').toLowerCase().contains(query);
    }).toList();
    final order = {for (var i = 0; i < _recent.length; i++) _recent[i].id: i};
    filtered.sort((a, b) {
      if (_sort == 'recent') {
        final byRecent = (order[a.id] ?? _recent.length)
            .compareTo(order[b.id] ?? _recent.length);
        if (byRecent != 0) return byRecent;
      }
      if (_sort == 'id') return a.id.compareTo(b.id);
      final nameA = _entry(a).alias.isEmpty ? a.id : _entry(a).alias;
      final nameB = _entry(b).alias.isEmpty ? b.id : _entry(b).alias;
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });
    return filtered;
  }

  Future<void> _edit([Peer? peer]) async {
    final previous = peer == null ? null : _entry(peer);
    final id = TextEditingController(text: previous?.id ?? '');
    final alias = TextEditingController(text: previous?.alias ?? '');
    final tags = TextEditingController(text: previous?.tags.join(', ') ?? '');
    final note = TextEditingController(text: previous?.note ?? '');
    var folder = previous?.folder ?? '';
    var saved = previous?.saved ?? true;
    var error = '';
    final result = await showDialog<LocalBookEntry>(context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) =>
        AlertDialog(
          title: Text(_text('Устройство', 'Device')),
          content: SizedBox(width: 430, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: id, readOnly: peer != null,
                decoration: const InputDecoration(labelText: 'ID'), maxLength: 256),
              TextField(controller: alias, maxLength: 256,
                decoration: InputDecoration(labelText: _text('Название', 'Name'))),
              DropdownButtonFormField<String>(value: folder, isExpanded: true,
                items: [DropdownMenuItem(value: '', child: Text(_text('Без папки', 'No folder'))),
                  ..._data.folders.map((f) => DropdownMenuItem(value: f, child: Text(f)))],
                onChanged: (v) => update(() => folder = v ?? '')),
              TextField(controller: tags, maxLength: 4000,
                decoration: InputDecoration(labelText: _text('Теги через запятую', 'Comma-separated tags'))),
              TextField(controller: note, maxLength: 4000, maxLines: 3,
                decoration: InputDecoration(labelText: _text('Заметки', 'Notes'))),
              CheckboxListTile(value: saved, contentPadding: EdgeInsets.zero,
                title: Text(_text('Сохранить в книге', 'Save in address book')),
                onChanged: (v) => update(() => saved = v ?? false)),
              if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
            ],
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: Text(_text('Отмена', 'Cancel'))),
            TextButton(onPressed: () {
              try {
                final entry = LocalBookEntry(id: id.text.trim().replaceAll(' ', ''),
                  alias: alias.text.trim(), folder: folder,
                  tags: tags.text.split(',').map((t) => t.trim())
                      .where((t) => t.isNotEmpty).toSet().toList(),
                  note: note.text, saved: saved);
                if (peer == null && (_data.entries.containsKey(entry.id) ||
                    _recent.any((p) => p.id == entry.id))) {
                  throw FormatException(_text('Этот ID уже есть. Измените его карточку.',
                      'This ID exists. Edit its card.'));
                }
                _data.withEntry(entry);
                Navigator.pop(dialogContext, entry);
              } catch (e) { update(() => error = e.toString()); }
            }, child: Text(_text('Сохранить', 'Save'))),
          ],
        )));
    id.dispose(); alias.dispose(); tags.dispose(); note.dispose();
    if (result != null && mounted) await _save(_data.withEntry(result));
  }

  Future<void> _addFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (context) =>
      AlertDialog(title: Text(_text('Новая папка', 'New folder')),
        content: TextField(controller: controller, maxLength: 256,
          decoration: InputDecoration(hintText: _text('Например: Офис/Бухгалтерия', 'Example: Office/Accounting'))),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
            child: Text(_text('Отмена', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(_text('Добавить', 'Add')))]));
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    if (_data.folders.contains(name)) {
      setState(() => _error = _text('Папка уже существует', 'Folder already exists'));
      return;
    }
    await _save(LocalBookData(folders: [..._data.folders, name], entries: _data.entries));
  }

  Future<bool> _confirm(String text) async => await showDialog<bool>(
    context: context, builder: (context) => AlertDialog(content: Text(text),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false),
        child: Text(_text('Отмена', 'Cancel'))),
        TextButton(onPressed: () => Navigator.pop(context, true),
          child: Text(_text('Продолжить', 'Continue')))])) ?? false;

  Future<void> _backup({required bool importing}) async {
    final controller = TextEditingController(text: importing ? '' :
        (_storageBroken ? bind.getLocalFlutterOption(k: _storageKey) : _data.encode()));
    var error = '';
    final result = await showDialog<LocalBookData>(context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text(importing ? _text('Импорт JSON', 'Import JSON') : _text('Резервная копия JSON', 'JSON backup')),
        content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_text('Скопируйте JSON в файл для резервной копии. Импорт заменяет локальную книгу.',
              'Copy JSON to a file for backup. Import replaces the local book.')),
          TextField(controller: controller, readOnly: !importing, maxLines: 8),
          if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: Text(_text('Закрыть', 'Close'))),
          if (!importing) TextButton(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: controller.text));
          }, child: Text(_text('Копировать', 'Copy'))),
          if (importing) TextButton(onPressed: () {
            try { Navigator.pop(dialogContext, LocalBookData.decode(controller.text)); }
            catch (e) { update(() => error = e.toString()); }
          }, child: Text(_text('Импортировать', 'Import'))),
        ],
      )));
    controller.dispose();
    if (result != null && mounted && await _confirm(_text(
        'Заменить локальную книгу? Сначала сохраните резервную копию текущих данных.',
        'Replace the local book? Back up your current data first.'))) {
      if (mounted) await _save(result, restoring: true);
    }
  }

  Future<void> _copyRemoteBook() async {
    final peers = gFFI.abModel.currentAbPeers.toList();
    if (peers.isEmpty) {
      setState(() => _error = _text('Откройте существующую адресную книгу, чтобы загрузить её устройства.',
          'Open your existing address book to load its devices.'));
      return;
    }
    var next = _data;
    try {
      for (final p in peers) {
        if (next.entries[p.id]?.saved == true) continue;
        final existing = next.entries[p.id];
        next = next.withEntry(LocalBookEntry(id: p.id,
          alias: existing?.alias.isNotEmpty == true ? existing!.alias : p.alias,
          folder: existing?.folder ?? '',
          tags: {...?existing?.tags, ...p.tags.map((t) => t.toString())}
              .where((t) => t.trim().isNotEmpty).toList(),
          note: existing?.note.isNotEmpty == true ? existing!.note : p.note, saved: true));
      }
      await _save(next);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    final tags = _data.entries.values.expand((e) => e.tags).toSet().toList()..sort();
    final peers = _peers();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.all(8), child: Text(_text(
        'Локальная книга — без подписки. Данные хранятся на этом устройстве.',
        'Local address book — no subscription. Data stays on this device.'))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Wrap(
        spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 200, child: TextField(
            decoration: InputDecoration(hintText: _text('Поиск', 'Search'), prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v))),
          DropdownButton<String>(value: _view, items: [
            DropdownMenuItem(value: 'all', child: Text(_text('Все', 'All'))),
            DropdownMenuItem(value: 'recent', child: Text(_text('Последние', 'Recent'))),
            DropdownMenuItem(value: 'saved', child: Text(_text('Сохранённые', 'Saved')))],
            onChanged: (v) => setState(() => _view = v ?? 'all')),
          DropdownButton<String>(value: _folder, hint: Text(_text('Все папки', 'All folders')),
            items: [DropdownMenuItem<String>(value: null, child: Text(_text('Все папки', 'All folders'))),
              DropdownMenuItem(value: '', child: Text(_text('Без папки', 'No folder'))),
              ..._data.folders.map((f) => DropdownMenuItem(value: f, child: Text(f)))],
            onChanged: (v) => setState(() => _folder = v)),
          DropdownButton<String>(value: _tag, hint: Text(_text('Все теги', 'All tags')),
            items: [DropdownMenuItem<String>(value: null, child: Text(_text('Все теги', 'All tags'))),
              ...tags.map((t) => DropdownMenuItem(value: t, child: Text(t)))],
            onChanged: (v) => setState(() => _tag = v)),
          DropdownButton<String>(value: _sort, items: [
            DropdownMenuItem(value: 'recent', child: Text(_text('По последним подключениям', 'Recent order'))),
            DropdownMenuItem(value: 'name', child: Text(_text('По имени', 'Name'))),
            const DropdownMenuItem(value: 'id', child: Text('ID'))],
            onChanged: (v) => setState(() => _sort = v ?? 'recent')),
        ],
      )),
      Padding(padding: const EdgeInsets.all(8), child: Wrap(spacing: 8, runSpacing: 4, children: [
        OutlinedButton(onPressed: _busy || _loading ? null : () => _edit(), child: Text(_text('Добавить устройство', 'Add device'))),
        OutlinedButton(onPressed: _busy || _loading ? null : _addFolder, child: Text(_text('Создать папку', 'New folder'))),
        if (_folder != null && _folder!.isNotEmpty) OutlinedButton(onPressed: _busy ? null : () async {
          final folder = _folder!;
          if (await _confirm(_text('Удалить папку? Устройства останутся без папки.',
              'Delete folder? Devices will move to no folder.')) && mounted) {
            await _save(_data.withoutFolder(folder));
          }
        }, child: Text(_text('Удалить папку', 'Delete folder'))),
        OutlinedButton(onPressed: _loading || _busy ? null : () async {
          setState(() => _loading = true); await _loadRecent();
        }, child: Text(_text('Обновить последние', 'Refresh recent'))),
        OutlinedButton(onPressed: _busy || _loading ? null : _copyRemoteBook,
            child: Text(_text('Копировать из адресной книги', 'Copy from address book'))),
        OutlinedButton(onPressed: _busy || _loading ? null : () => _backup(importing: false), child: Text(_text('Экспорт JSON', 'Export JSON'))),
        OutlinedButton(onPressed: _busy || _loading ? null : () => _backup(importing: true), child: Text(_text('Импорт JSON', 'Import JSON'))),
      ])),
      if (_error.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_error, style: const TextStyle(color: Colors.red))),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) :
        peers.isEmpty ? Center(child: Text(_text('Нет устройств. Добавьте ID или измените фильтр.', 'No devices. Add an ID or change the filter.'))) :
        ListView.builder(itemCount: peers.length, itemBuilder: (context, index) {
          final peer = peers[index]; final e = _entry(peer);
          return Card(child: ListTile(
            title: Text(e.alias.isEmpty ? peer.id : e.alias),
            subtitle: Text([peer.id, if (e.folder.isNotEmpty) e.folder,
              if (e.tags.isNotEmpty) e.tags.join(', '), if (e.note.isNotEmpty) e.note,
              if (e.saved) _text('В книге', 'Saved')].join(' · ')),
            onTap: _busy ? null : () => _edit(peer),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: _text('Изменить папку и теги', 'Edit folder and tags'),
                onPressed: _busy ? null : () => _edit(peer), icon: const Icon(Icons.edit)),
              IconButton(tooltip: e.saved ? _text('Убрать из книги', 'Remove from book') : _text('Сохранить в книге', 'Save in book'),
                onPressed: _busy ? null : () => _save(_data.withEntry(LocalBookEntry(
                  id: e.id, alias: e.alias, folder: e.folder, tags: e.tags, note: e.note, saved: !e.saved))),
                icon: Icon(e.saved ? Icons.bookmark : Icons.bookmark_border)),
              IconButton(tooltip: _text('Подключиться', 'Connect'),
                onPressed: () => connect(context, peer.id), icon: const Icon(Icons.play_arrow)),
            ]),
          ));
        })),
    ]);
  }
}
