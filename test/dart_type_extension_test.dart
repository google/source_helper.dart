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
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:source_helper/source_helper.dart';
import 'package:test/test.dart';

import 'src/resolve.dart';

const _source = '''
enum Color {
  red,
  green,
  blue;

  static const Color fallback = red;

  static Color get first => red;
}

class Holder {
  int nonNullInt = 0;
  int? nullableInt;
  num number = 0;
  String text = '';
  List<String>? nullableList;
  List<int> ints = const [];
  Map<String, int> map = const {};
  Color color = Color.red;
  Color? nullableColor;
  dynamic dyn;
  Object? nullableObject;
  Object object = 0;
}
''';

void main() {
  late ClassElement holder;
  DartType type(String fieldName) => holder.field(fieldName).type;

  setUpAll(() async {
    holder = (await resolveSource(_source)).element.cls('Holder');
  });

  group('toStringNonNullable', () {
    const cases = {
      'nonNullInt': 'int',
      'nullableInt': 'int',
      'nullableList': 'List<String>',
      'ints': 'List<int>',
      'dyn': 'dynamic',
      'nullableObject': 'Object',
      'object': 'Object',
    };
    for (final MapEntry(key: field, value: expected) in cases.entries) {
      test(field, () {
        expect(type(field).toStringNonNullable(), expected);
      });
    }
  });

  group('enumConstants', () {
    test('enum type lists constants in declaration order', () {
      expect(type('color').enumConstants.names, ['red', 'green', 'blue']);
    });

    test('nullable enum type lists constants', () {
      expect(type('nullableColor').enumConstants.names, [
        'red',
        'green',
        'blue',
      ]);
    });

    test('static members of the enum are excluded', () {
      final names = type('color').enumConstants.names;
      expect(names, isNot(contains('fallback')));
      expect(names, isNot(contains('first')));
    });

    test('non-enum types return an empty list', () {
      expect(type('nonNullInt').enumConstants, isEmpty);
      expect(type('dyn').enumConstants, isEmpty);
      expect(type('ints').enumConstants, isEmpty);
    });
  });

  group('isEnum', () {
    test('enum type', () {
      expect(type('color').isEnum, isTrue);
      expect(type('nullableColor').isEnum, isTrue);
    });

    test('non-enum type', () {
      expect(type('nonNullInt').isEnum, isFalse);
      expect(type('dyn').isEnum, isFalse);
    });
  });

  group('isNullableType', () {
    test('nullable', () {
      expect(type('nullableInt').isNullableType, isTrue);
      expect(type('dyn').isNullableType, isTrue);
      expect(type('nullableObject').isNullableType, isTrue);
    });

    test('non-nullable', () {
      expect(type('nonNullInt').isNullableType, isFalse);
      expect(type('object').isNullableType, isFalse);
    });
  });

  group('isLikeDynamic', () {
    test('dynamic and Object?', () {
      expect(type('dyn').isLikeDynamic, isTrue);
      expect(type('nullableObject').isLikeDynamic, isTrue);
    });

    test('Object and int?', () {
      expect(type('object').isLikeDynamic, isFalse);
      expect(type('nullableInt').isLikeDynamic, isFalse);
    });
  });

  group('typeArgumentsOf', () {
    const iterableChecker = TypeChecker.typeNamed(
      Iterable,
      inPackage: 'core',
      inSdk: true,
    );

    test('List<int> implements Iterable<int>', () {
      final args = type('ints').typeArgumentsOf(iterableChecker);
      expect(args, isNotNull);
      expect(args!.map((t) => t.getDisplayString()), ['int']);
    });

    test('Map<String, int> does not implement Iterable', () {
      expect(type('map').typeArgumentsOf(iterableChecker), isNull);
    });
  });

  group('isAssignableTo', () {
    test('int to num', () {
      expect(type('nonNullInt').isAssignableTo(type('number')), isTrue);
    });

    test('String to int', () {
      expect(type('text').isAssignableTo(type('nonNullInt')), isFalse);
    });
  });
}
