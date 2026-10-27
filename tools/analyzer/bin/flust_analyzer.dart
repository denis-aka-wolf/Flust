import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    try {
      final request = jsonDecode(line) as Map<String, dynamic>;
      final id = request['id']?.toString() ?? '';
      if (request['method'] != 'parse') {
        _write({'id': id, 'ok': false, 'error': 'Unsupported method: ${request['method']}'});
        return;
      }
      final source = request['source']?.toString() ?? '';
      final uri = request['uri']?.toString() ?? '';
      final model = _parseSource(uri, source);
      _write({'id': id, 'ok': true, 'model': model});
    } catch (error) {
      _write({'id': '', 'ok': false, 'error': error.toString()});
    }
  }, onError: (Object error) {
    stderr.writeln('Flust Analyzer input error: $error');
  });
}

void _write(Map<String, Object?> value) {
  stdout.writeln(jsonEncode(value));
}

Map<String, Object?> _parseSource(String uri, String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final rootExpression = _findBuildRoot(result.unit);
  var nextId = 0;

  Map<String, Object?>? buildNode(InstanceCreationExpression node) {
    final id = 'node-${nextId++}';
    final name = node.constructorName.type.name2.lexeme;
    final properties = <String, Object?>{};
    final children = <Map<String, Object?>>[];

    for (final argument in node.argumentList.arguments) {
      if (argument is! NamedExpression) continue;

      final key = argument.name.label.name;
      final value = argument.expression;
      if (key == 'child') {
        children.addAll(widgetNodes(value));
      } else if (key == 'children') {
        children.addAll(widgetNodes(value));
      } else {
        properties[key] = {
          'kind': value is StringLiteral ||
                  value is IntegerLiteral ||
                  value is DoubleLiteral ||
                  value is BooleanLiteral
              ? 'literal'
              : 'expression',
          'code': source.substring(value.offset, value.end),
        };
      }
    }

    return {
      'id': id,
      'kind': 'widget',
      'name': name,
      'source': {'start': node.offset, 'end': node.end},
      'properties': properties,
      'children': children,
    };
  }

  List<Map<String, Object?>> widgetNodes(Expression expression) {
    if (expression is InstanceCreationExpression) {
      final node = buildNode(expression);
      return node == null ? [] : [node];
    }
    if (expression is ListLiteral) {
      final nodes = <Map<String, Object?>>[];
      for (final element in expression.elements) {
        if (element is Expression) nodes.addAll(widgetNodes(element));
      }
      return nodes;
    }
    // Collection-if/for and conditional expressions can be added here later.
    return [];
  }

  final root = rootExpression is InstanceCreationExpression
      ? buildNode(rootExpression)
      : null;

  final diagnostics = result.errors.map((error) => {
    'message': error.message,
    'offset': error.offset,
    'length': error.length,
  }).toList();

  return {
    'schemaVersion': 1,
    'uri': uri,
    'root': root,
    'diagnostics': diagnostics,
  };
}

Expression? _findBuildRoot(CompilationUnit unit) {
  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration) continue;
    for (final member in declaration.members) {
      if (member is! MethodDeclaration || member.name.lexeme != 'build') {
        continue;
      }
      final body = member.body;
      if (body is ExpressionFunctionBody) return body.expression;
      if (body is BlockFunctionBody) {
        for (final statement in body.block.statements) {
          if (statement is ReturnStatement) return statement.expression;
        }
      }
    }
  }
  return null;
}
