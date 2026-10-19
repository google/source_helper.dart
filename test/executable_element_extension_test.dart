// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@TestOn('vm')
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:source_helper/source_helper.dart';
import 'package:test/test.dart';

import 'src/resolve.dart';

const _source = '''
int topLevel(int x) => x;

class Foo {
  Foo();

  Foo.named();

  static int staticMethod() => 1;

  int instanceMethod() => 2;

  int get prop => 3;
}

extension NamedExt on int {
  static int staticExt() => 1;
  int instanceExt() => 2;
}

extension on int {
  static int unnamedStaticExt() => 1;
  int unnamedInstanceExt() => unnamedStaticExt();
}

void outer() {
  int local() => 1;
  local();
  0.unnamedInstanceExt();
}
''';

void main() {
  late LibraryElement library;
  late ClassElement foo;
  late ExecutableElement localFunction;

  setUpAll(() async {
    final result = await resolveSource(_source);
    library = result.element;
    foo = library.cls('Foo');

    final outer = result.units.first.unit.declarations
        .whereType<FunctionDeclaration>()
        .singleWhere((d) => d.name.lexeme == 'outer');
    final body = outer.functionExpression.body as BlockFunctionBody;
    final statement = body.block.statements
        .whereType<FunctionDeclarationStatement>()
        .single;
    localFunction = statement.functionDeclaration.declaredFragment!.element;
  });

  test('top-level function', () {
    final fn = library.topLevelFunctions.singleWhere(
      (f) => f.name == 'topLevel',
    );
    expect(fn.qualifiedName, 'topLevel');
  });

  test('static method', () {
    expect(foo.getMethod('staticMethod')!.qualifiedName, 'Foo.staticMethod');
  });

  test('instance method throws', () {
    expect(
      () => foo.getMethod('instanceMethod')!.qualifiedName,
      throwsUnsupportedError,
    );
  });

  test('named extension static method', () {
    final ext = library.extensions.singleWhere((e) => e.name == 'NamedExt');
    expect(ext.getMethod('staticExt')!.qualifiedName, 'NamedExt.staticExt');
  });

  test('named extension instance method throws', () {
    final ext = library.extensions.singleWhere((e) => e.name == 'NamedExt');
    expect(
      () => ext.getMethod('instanceExt')!.qualifiedName,
      throwsUnsupportedError,
    );
  });

  test('unnamed extension methods throw', () {
    final ext = library.extensions.singleWhere((e) => e.name == null);
    expect(
      () => ext.getMethod('unnamedStaticExt')!.qualifiedName,
      throwsUnsupportedError,
    );
    expect(
      () => ext.getMethod('unnamedInstanceExt')!.qualifiedName,
      throwsUnsupportedError,
    );
  });

  test('unnamed constructor', () {
    expect(foo.unnamedConstructor!.qualifiedName, 'Foo');
  });

  test('named constructor', () {
    expect(foo.getNamedConstructor('named')!.qualifiedName, 'Foo.named');
  });

  test('getter throws', () {
    expect(() => foo.getGetter('prop')!.qualifiedName, throwsUnsupportedError);
  });

  test('local function throws', () {
    expect(() => localFunction.qualifiedName, throwsUnsupportedError);
  });
}
