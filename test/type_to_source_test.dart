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

import 'package:analyzer/dart/element/element.dart';
import 'package:source_helper/source_helper.dart';
import 'package:test/test.dart';

import 'src/resolve.dart';

const _source = '''
import 'dart:async' as async;
import 'dart:collection' as c show LinkedHashMap;

import 'base.dart' show Base;
import 'other.dart' as o;
import 'other.dart' show Visible;

typedef Local<T> = Map<String, T>;

typedef NullableLocal = int?;

typedef Box<T> = T;

abstract class Fields<T extends num> {
  abstract int plain;
  abstract String? nullable;
  abstract List<int?> typeArgument;
  abstract T typeParameter;
  abstract T? nullableTypeParameter;
  abstract dynamic dynamicType;
  abstract void Function() voidReturn;
  abstract async.Completer<int>? prefixed;
  abstract c.LinkedHashMap<String, async.Completer<T>> nestedPrefixed;
  abstract o.Other<int> prefixedLocalLibrary;
  abstract Visible shownWithoutPrefix;
  abstract Local<int>? localAlias;
  abstract NullableLocal nullableAlias;
  abstract Box<int?> nullableArgAlias;
  abstract o.OtherAlias? prefixedAlias;
  abstract (int, {String name})? record;
  abstract (o.Other<int>,) singlePositionalRecord;
  abstract ({int a, String? b}) namedRecord;
  abstract void Function(int, {required String name, o.Other<int>? other})?
  namedParameters;
  abstract T Function<S, U extends T>(S, U, [int, String?]) genericFunction;
}

class Sub extends Base {}
''';

const _other = '''
class Other<T> {}

class Visible {}

typedef OtherAlias = List<Other<int>>;
''';

const _base = '''
typedef Ints = List<int>;

class Unimported {}

class Base {
  Ints? inherited;
  Unimported? unimportedField;
}
''';

void main() {
  late LibraryElement library;

  setUpAll(() async {
    library = (await resolveSource(
      _source,
      extraFiles: {'other.dart': _other, 'base.dart': _base},
    )).element;
  });

  String fieldCode(String name) =>
      typeToSource(library.cls('Fields').field(name).type, library: library);

  group('typeToSource', () {
    for (final MapEntry(key: name, value: expected) in {
      'plain': 'int',
      'nullable': 'String?',
      'typeArgument': 'List<int?>',
      'typeParameter': 'T',
      'nullableTypeParameter': 'T?',
      'dynamicType': 'dynamic',
      'voidReturn': 'void Function()',
      'prefixed': 'async.Completer<int>?',
      'nestedPrefixed': 'c.LinkedHashMap<String, async.Completer<T>>',
      'prefixedLocalLibrary': 'o.Other<int>',
      'shownWithoutPrefix': 'Visible',
      'localAlias': 'Local<int>?',
      'nullableAlias': 'NullableLocal',
      'nullableArgAlias': 'Box<int?>',
      'prefixedAlias': 'o.OtherAlias?',
      'record': '(int, {String name})?',
      'singlePositionalRecord': '(o.Other<int>,)',
      'namedRecord': '({int a, String? b})',
      'namedParameters':
          'void Function(int, {required String name, o.Other<int>? other})?',
      'genericFunction': 'T Function<S, U extends T>(S, U, [int, String?])',
    }.entries) {
      test('$name is `$expected`', () {
        expect(fieldCode(name), expected);
      });
    }

    test('an alias that is not imported is written as the aliased type', () {
      final inherited = library
          .cls('Sub')
          .supertype!
          .element
          .getField('inherited')!;
      expect(inherited.type.alias, isNotNull);
      expect(typeToSource(inherited.type, library: library), 'List<int>?');
    });

    test('a class that is not imported falls back to its bare name', () {
      final unimported = library
          .cls('Sub')
          .supertype!
          .element
          .getField('unimportedField')!;
      expect(typeToSource(unimported.type, library: library), 'Unimported?');
    });

    test('the result depends on the library it is written for', () {
      final other = library.firstFragment.importedLibraries.singleWhere(
        (l) => l.getClass('Other') != null,
      );
      final type = library.cls('Fields').field('prefixedAlias').type;
      expect(typeToSource(type, library: other), 'OtherAlias?');
    });
  });
}
