import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String source;
  late Map<String, dynamic> response;

  setUpAll(() async {
    final sourceFile = File(
      '../../examples/flutter_app/lib/widgets/profile_card.w.dart',
    );

    expect(
      sourceFile.existsSync(),
      isTrue,
      reason: 'Не найден profile_card.w.dart: ${sourceFile.absolute.path}',
    );

    source = await sourceFile.readAsString();

    final process = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'bin/flust_analyzer.dart'],
      workingDirectory: Directory.current.path,
    );

    final stdoutFuture = process.stdout
        .transform(utf8.decoder)
        .join();

    final stderrFuture = process.stderr
        .transform(utf8.decoder)
        .join();

    process.stdin.writeln(
      jsonEncode({
        'id': 'profile-card-test',
        'method': 'parse',
        'uri': 'file:///profile_card.w.dart',
        'source': source,
      }),
    );

    await process.stdin.close();

    final exitCode = await process.exitCode;
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;

    expect(
      exitCode,
      equals(0),
      reason: 'Анализатор завершился с ошибкой.\nstderr:\n$stderr',
    );

    final lines = stdout
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();

    expect(
      lines,
      hasLength(1),
      reason: 'Ожидалась одна JSON-строка ответа.\nstdout:\n$stdout',
    );

    final decoded = jsonDecode(lines.single);

    expect(
      decoded,
      isA<Map<String, dynamic>>(),
      reason: 'Ответ анализатора должен быть JSON-объектом.',
    );

    response = decoded as Map<String, dynamic>;
  });

  group('Flust Analyzer: profile_card.w.dart', () {
    test('возвращает успешный ответ протокола', () {
      expect(response['id'], equals('profile-card-test'));
      expect(response['ok'], isTrue);
      expect(response['model'], isA<Map<String, dynamic>>());
    });

    test('находит корневой виджет Card', () {
      final model = response['model'] as Map<String, dynamic>;
      final root = model['root'];

      expect(
        root,
        isA<Map<String, dynamic>>(),
        reason: 'Анализатор вернул root: null.',
      );

      expect(root['kind'], equals('widget'));
      expect(root['name'], equals('Card'));
    });

    test('строит правильную вложенность виджетов', () {
      final model = response['model'] as Map<String, dynamic>;
      final root = model['root'] as Map<String, dynamic>;

      final padding = _childNamed(root, 'Padding');
      final column = _childNamed(padding, 'Column');

      expect(
        column['children'],
        isA<List<dynamic>>(),
      );

      final children = column['children'] as List<dynamic>;

      final names = children
          .map((child) => (child as Map<String, dynamic>)['name'])
          .toList();

      expect(
        names,
        equals([
          'CircleAvatar',
          'SizedBox',
          'Text',
          'Text',
          'SizedBox',
          'FilledButton',
        ]),
      );
    });

    test('каждый узел дерева содержит необходимые поля', () {
      final model = response['model'] as Map<String, dynamic>;
      final root = model['root'] as Map<String, dynamic>;

      void checkNode(Map<String, dynamic> node) {
        expect(node['id'], isA<String>());
        expect(node['kind'], equals('widget'));
        expect(node['name'], isA<String>());
        expect(node['source'], isA<Map<String, dynamic>>());
        expect(node['properties'], isA<Map<String, dynamic>>());
        expect(node['children'], isA<List<dynamic>>());

        final children = node['children'] as List<dynamic>;

        for (final child in children) {
          checkNode(child as Map<String, dynamic>);
        }
      }

      checkNode(root);
    });

    test('не содержит синтаксических диагностик', () {
      final model = response['model'] as Map<String, dynamic>;
      final diagnostics = model['diagnostics'];

      expect(diagnostics, isA<List<dynamic>>());
      expect(
        diagnostics,
        isEmpty,
        reason: 'Обнаружены ошибки разбора: $diagnostics',
      );
    });

    test('сохраняет исходный URI и версию схемы', () {
      final model = response['model'] as Map<String, dynamic>;

      expect(model['schemaVersion'], equals(1));
      expect(model['uri'], equals('file:///profile_card.w.dart'));
    });
  });
}

Map<String, dynamic> _childNamed(
  Map<String, dynamic> parent,
  String name,
) {
  final children = parent['children'] as List<dynamic>;

  for (final child in children) {
    final node = child as Map<String, dynamic>;

    if (node['name'] == name) {
      return node;
    }
  }

  fail(
    'В дочерних узлах ${parent['name']} не найден виджет $name. '
    'Найденные узлы: ${children.map((child) => child['name']).toList()}',
  );
}