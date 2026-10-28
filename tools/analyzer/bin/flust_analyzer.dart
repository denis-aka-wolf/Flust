import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Flust Analyzer
///
/// Protocol:
/// - Transport: JSON Lines over stdin/stdout.
/// - One input line represents one JSON request.
/// - One output line represents one JSON response.
Future<void> main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) {
      continue;
    }

    Object? requestId;

    try {
      final decoded = jsonDecode(line);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Request must be a JSON object.',
        );
      }

      final request = decoded;
      requestId = request['id'];

      final method = request['method'];

      if (method != 'parse') {
        throw FormatException(
          'Unsupported method: $method',
        );
      }

      final uri = request['uri'] is String
          ? request['uri'] as String
          : 'file:///unknown.dart';

      final source = request['source'] is String
          ? request['source'] as String
          : '';

      final model = _parseSource(uri, source);

      stdout.writeln(
        jsonEncode({
          'id': requestId,
          'ok': true,
          'model': model,
        }),
      );
    } catch (error) {
      stdout.writeln(
        jsonEncode({
          'id': requestId,
          'ok': false,
          'error': error.toString(),
        }),
      );
    }
  }
}

/// Parses Dart source and produces the Flust visual tree model.
Map<String, Object?> _parseSource(
  String uri,
  String source,
) {
  final result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );

  final rootExpression = _findBuildRoot(result.unit);

  var nextId = 0;

  // The two local functions refer to each other.
  // Declare widgetNodes before buildNode to avoid
  // the referenced_before_declaration error.
  late final List<Map<String, Object?>> Function(Expression)
      widgetNodes;

  Map<String, Object?> buildNode(
    InstanceCreationExpression node,
  ) {
    final id = 'node-${nextId++}';

    // Use the type name, e.g. Card, Padding, Column.
    // A constructor such as EdgeInsets.all is not treated
    // as a widget unless it appears in a child position.
    final name = node.constructorName.type.name2.lexeme;

    final properties = <String, Object?>{};
    final children = <Map<String, Object?>>[];

    for (final argument in node.argumentList.arguments) {
      if (argument is! NamedExpression) {
        continue;
      }

      final key = argument.name.label.name;
      final value = argument.expression;

      if (key == 'child') {
        children.addAll(widgetNodes(value));
        continue;
      }

      if (key == 'children') {
        children.addAll(widgetNodes(value));
        continue;
      }

      properties[key] = {
        'kind': _isLiteral(value) ? 'literal' : 'expression',
        'code': source.substring(value.offset, value.end),
      };
    }

    return {
      'id': id,
      'kind': 'widget',
      'name': name,
      'source': {
        'start': node.offset,
        'end': node.end,
      },
      'properties': properties,
      'children': children,
    };
  }

  // Extract widget nodes from child/children expressions.
  //
  // Examples:
  //   child: const Text('Hello')
  //   children: [const Text('One'), const Text('Two')]
  //
  // The function is assigned before it is called.
  widgetNodes = (Expression expression) {
    final unwrapped = _unwrapExpression(expression);

    if (unwrapped is InstanceCreationExpression) {
      return <Map<String, Object?>>[
        buildNode(unwrapped),
      ];
    }

    if (unwrapped is ListLiteral) {
      final nodes = <Map<String, Object?>>[];

      for (final element in unwrapped.elements) {
        if (element is Expression) {
          nodes.addAll(widgetNodes(element));
        } else if (element is IfElement) {
          nodes.addAll(_widgetNodesFromIfElement(
            element,
            widgetNodes,
          ));
        } else if (element is ForElement) {
          nodes.addAll(
            _widgetNodesFromCollectionElement(
              element.body,
              widgetNodes,
            ),
          );
        }
      }

      return nodes;
    }

    if (unwrapped is ConditionalExpression) {
      return <Map<String, Object?>>[
        ...widgetNodes(unwrapped.thenExpression),
        ...widgetNodes(unwrapped.elseExpression),
      ];
    }

    return <Map<String, Object?>>[];
  };

  final root = rootExpression == null
      ? null
      : _buildRootNode(
          rootExpression,
          buildNode,
          widgetNodes,
        );

  final diagnostics = result.errors.map((error) {
    return <String, Object?>{
      'message': error.message,
      'offset': error.offset,
      'length': error.length,
    };
  }).toList();

  return {
    'schemaVersion': 1,
    'uri': uri,
    'root': root,
    'diagnostics': diagnostics,
  };
}

/// Converts the build() return expression into the root widget node.
Map<String, Object?>? _buildRootNode(
  Expression expression,
  Map<String, Object?> Function(InstanceCreationExpression) buildNode,
  List<Map<String, Object?>> Function(Expression) widgetNodes,
) {
  final unwrapped = _unwrapExpression(expression);

  if (unwrapped is InstanceCreationExpression) {
    return buildNode(unwrapped);
  }

  final nodes = widgetNodes(unwrapped);

  if (nodes.isNotEmpty) {
    return nodes.first;
  }

  return null;
}

/// Finds the expression returned by a method named build().
///
/// Supports both:
///
/// Widget build(BuildContext context) => const Text('Hello');
///
/// and:
///
/// Widget build(BuildContext context) {
///   return const Text('Hello');
/// }
Expression? _findBuildRoot(CompilationUnit unit) {
  final visitor = _BuildMethodVisitor();
  unit.accept(visitor);
  return visitor.root;
}

class _BuildMethodVisitor extends RecursiveAstVisitor<void> {
  Expression? root;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (root == null && node.name.lexeme == 'build') {
      root = _readBuildBody(node.body);
    }

    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (root == null && node.name.lexeme == 'build') {
      root = _readBuildBody(node.functionExpression.body);
    }

    super.visitFunctionDeclaration(node);
  }

  Expression? _readBuildBody(FunctionBody body) {
    if (body is ExpressionFunctionBody) {
      return body.expression;
    }

    if (body is BlockFunctionBody) {
      final returnVisitor = _ReturnExpressionVisitor();
      body.block.accept(returnVisitor);
      return returnVisitor.expression;
    }

    return null;
  }
}

/// Finds the first return expression in a block.
class _ReturnExpressionVisitor extends RecursiveAstVisitor<void> {
  Expression? expression;

  @override
  void visitReturnStatement(ReturnStatement node) {
    expression ??= node.expression;
    super.visitReturnStatement(node);
  }
}

/// Handles widget expressions inside an if collection element.
List<Map<String, Object?>> _widgetNodesFromIfElement(
  IfElement element,
  List<Map<String, Object?>> Function(Expression) widgetNodes,
) {
  final nodes = <Map<String, Object?>>[];

  nodes.addAll(
    _widgetNodesFromCollectionElement(
      element.thenElement,
      widgetNodes,
    ),
  );

  final elseElement = element.elseElement;

  if (elseElement != null) {
    nodes.addAll(
      _widgetNodesFromCollectionElement(
        elseElement,
        widgetNodes,
      ),
    );
  }

  return nodes;
}

/// Converts a collection element into widget nodes.
List<Map<String, Object?>> _widgetNodesFromCollectionElement(
  CollectionElement element,
  List<Map<String, Object?>> Function(Expression) widgetNodes,
) {
  if (element is Expression) {
    return widgetNodes(element);
  }

  if (element is IfElement) {
    return _widgetNodesFromIfElement(
      element,
      widgetNodes,
    );
  }

  if (element is ForElement) {
    return _widgetNodesFromCollectionElement(
      element.body,
      widgetNodes,
    );
  }

  return <Map<String, Object?>>[];
}

/// Removes surrounding parentheses from an expression.
Expression _unwrapExpression(Expression expression) {
  var current = expression;

  while (current is ParenthesizedExpression) {
    current = current.expression;
  }

  return current;
}

/// Determines whether an expression is a simple literal.
bool _isLiteral(Expression expression) {
  final value = _unwrapExpression(expression);

  return value is StringLiteral ||
      value is IntegerLiteral ||
      value is DoubleLiteral ||
      value is BooleanLiteral ||
      value is NullLiteral;
}