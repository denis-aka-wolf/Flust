import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

void main() {
  final file = File(
    r'F:\Dart\Flust\examples\flutter_app\lib\widgets\profile_card.w.dart',
  );

  final source = file.readAsStringSync();
  final result = parseString(
    content: source,
    throwIfDiagnostics: false,
  );

  print('=== PARSE ERRORS ===');
  for (final error in result.errors) {
    print(error.message);
  }

  print('\n=== CLASSES ===');
  for (final declaration in result.unit.declarations) {
    if (declaration is ClassDeclaration) {
      print('Class: ${declaration.name.lexeme}');

      for (final member in declaration.members) {
        if (member is MethodDeclaration) {
          print('  Method: ${member.name.lexeme}');
          print('  Body: ${member.body.runtimeType}');

          if (member.name.lexeme == 'build') {
            print('  Build body: ${member.body}');
          }
        }
      }
    }
  }

  print('\n=== ALL BUILD DECLARATIONS ===');
  result.unit.accept(_DebugVisitor());
}

class _DebugVisitor extends RecursiveAstVisitor<void> {
  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'build') {
      print('MethodDeclaration: ${node.toSource()}');
    }

    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.name.lexeme == 'build') {
      print('FunctionDeclaration: ${node.toSource()}');
    }

    super.visitFunctionDeclaration(node);
  }
}