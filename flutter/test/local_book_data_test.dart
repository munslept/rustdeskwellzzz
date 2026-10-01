import 'package:flutter_hbb/models/local_book_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved and recent-only devices retain folders and tags after restart', () {
    final book = LocalBookData(folders: ['Office', 'Office/Accounting'])
        .withEntry(const LocalBookEntry(id: '123456789', alias: 'Work PC',
            folder: 'Office/Accounting', tags: ['work', 'urgent'], saved: true))
        .withEntry(const LocalBookEntry(id: '987654321', folder: 'Office',
            tags: ['home'], saved: false));
    final restored = LocalBookData.decode(book.encode());
    expect(restored.entries['123456789']!.saved, isTrue);
    expect(restored.entries['123456789']!.folder, 'Office/Accounting');
    expect(restored.entries['123456789']!.tags, ['work', 'urgent']);
    expect(restored.entries['987654321']!.saved, isFalse);
    expect(restored.entries['987654321']!.tags, ['home']);
  });

  test('deleting a folder preserves devices and their tags', () {
    final book = LocalBookData(folders: ['Office']).withEntry(
        const LocalBookEntry(id: '123', folder: 'Office',
            alias: 'PC', tags: ['work'], note: 'Desk 4', saved: true));
    final updated = LocalBookData.decode(book.withoutFolder('Office').encode());
    expect(updated.folders, isEmpty);
    expect(updated.entries['123']!.folder, isEmpty);
    expect(updated.entries['123']!.tags, ['work']);
    expect(updated.entries['123']!.note, 'Desk 4');
    expect(updated.entries['123']!.saved, isTrue);
  });

  test('invalid backups are rejected instead of overwriting the book', () {
    final book = LocalBookData().withEntry(const LocalBookEntry(id: '123', saved: true));
    expect(() => LocalBookData.decode('{"version":2,"folders":[],"entries":[]}'),
        throwsFormatException);
    expect(() => book.withEntry(const LocalBookEntry(id: '123', folder: 'missing')),
        throwsFormatException);
    expect(book.entries['123']!.folder, isEmpty);
    expect(() => LocalBookData.decode('{"version":1,"folders":[],"entries":[ '
        '{"id":"123","alias":"","folder":"","tags":[],"note":"","saved":true},'
        '{"id":"123","alias":"","folder":"","tags":[],"note":"","saved":false}]}'),
        throwsFormatException);
  });
}
