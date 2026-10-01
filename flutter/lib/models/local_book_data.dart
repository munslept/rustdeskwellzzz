import 'dart:convert';

/// Local metadata only. Credentials from remote address books are never copied.
class LocalBookEntry {
  final String id;
  final String alias;
  final String folder;
  final List<String> tags;
  final String note;
  final bool saved;

  const LocalBookEntry({required this.id, this.alias = '', this.folder = '',
    this.tags = const [], this.note = '', this.saved = false});

  Map<String, dynamic> toJson() => {'id': id, 'alias': alias, 'folder': folder,
    'tags': tags, 'note': note, 'saved': saved};

  factory LocalBookEntry.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final alias = value['alias'];
    final folder = value['folder'];
    final tags = value['tags'];
    final note = value['note'];
    final saved = value['saved'];
    if (id is! String || id.isEmpty || id.length > 256 ||
        RegExp(r'[\s\x00-\x1f]').hasMatch(id) ||
        alias is! String || alias.length > 256 ||
        folder is! String || folder.length > 256 ||
        tags is! List || tags.length > 50 ||
        tags.any((t) => t is! String || t.trim().isEmpty || t.length > 80) ||
        note is! String || note.length > 4000 || saved is! bool) {
      throw const FormatException('Invalid local address book entry');
    }
    return LocalBookEntry(id: id, alias: alias, folder: folder,
      tags: tags.cast<String>().toSet().toList(), note: note, saved: saved);
  }
}

class LocalBookData {
  final List<String> folders;
  final Map<String, LocalBookEntry> entries;
  LocalBookData({List<String>? folders, Map<String, LocalBookEntry>? entries})
      : folders = List.of(folders ?? []), entries = Map.of(entries ?? {});

  factory LocalBookData.decode(String raw) {
    if (raw.length > 20 * 1024 * 1024) {
      throw const FormatException('Address book exceeds 20 MB');
    }
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> || value['version'] != 1 ||
        value['folders'] is! List || value['entries'] is! List) {
      throw const FormatException('Invalid local address book format');
    }
    final folders = value['folders'] as List;
    final entries = value['entries'] as List;
    if (folders.length > 1000 || entries.length > 10000 ||
        folders.any((f) => f is! String || f.trim().isEmpty || f.length > 256) ||
        folders.toSet().length != folders.length) {
      throw const FormatException('Invalid folders or too many entries');
    }
    final result = LocalBookData(folders: folders.cast<String>());
    for (final item in entries) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid entry');
      }
      final entry = LocalBookEntry.fromJson(item);
      if (result.entries.containsKey(entry.id) ||
          (entry.folder.isNotEmpty && !result.folders.contains(entry.folder))) {
        throw const FormatException('Duplicate ID or unknown folder');
      }
      result.entries[entry.id] = entry;
    }
    return result;
  }

  String encode() => jsonEncode({'version': 1, 'folders': folders,
    'entries': entries.values.map((e) => e.toJson()).toList()});

  LocalBookData withEntry(LocalBookEntry entry) {
    final next = LocalBookData(folders: folders, entries: entries);
    next.entries[entry.id] = entry;
    return LocalBookData.decode(next.encode());
  }

  LocalBookData withoutFolder(String folder) {
    final next = LocalBookData(folders: folders.where((f) => f != folder).toList());
    for (final e in entries.values) {
      next.entries[e.id] = e.folder == folder
          ? LocalBookEntry(id: e.id, alias: e.alias, tags: e.tags,
              note: e.note, saved: e.saved)
          : e;
    }
    return next;
  }
}
