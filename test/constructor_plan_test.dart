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
import 'package:source_gen/source_gen.dart';
import 'package:source_helper/source_helper.dart';
import 'package:test/test.dart';

import 'src/resolve.dart';

const _source = '''
class Ctors {
  final int a;
  final String b;
  int? c;

  Ctors(this.a, this.b, {this.c});

  Ctors.optional(this.a, [this.b = '', int? extra]) : c = extra;

  Ctors.named(this.a, {required this.b, this.c, int? d});
}

class NoDefault {
  NoDefault.only();
}

class Plain {}

class Generic<T extends num, S> {}

class NullableBound<T extends Object?> {}
''';

void main() {
  late LibraryElement library;
  late ClassElement ctors;

  setUpAll(() async {
    library = (await resolveSource(_source)).element;
    ctors = library.cls('Ctors');
  });

  group('constructorByName', () {
    test('empty name selects the unnamed constructor', () {
      expect(constructorByName(ctors, ''), same(ctors.unnamedConstructor));
    });

    test('selects a named constructor', () {
      expect(
        constructorByName(ctors, 'named'),
        same(ctors.getNamedConstructor('named')),
      );
    });

    test('missing unnamed constructor', () {
      final noDefault = library.cls('NoDefault');
      expect(
        () => constructorByName(noDefault, ''),
        throwsA(
          isA<InvalidGenerationSourceError>()
              .having(
                (e) => e.message,
                'message',
                'The class `NoDefault` has no default constructor.',
              )
              .having((e) => e.element, 'element', same(noDefault)),
        ),
      );
    });

    test('missing named constructor', () {
      expect(
        () => constructorByName(ctors, 'missing'),
        throwsA(
          isA<InvalidGenerationSourceError>()
              .having(
                (e) => e.message,
                'message',
                'The class `Ctors` does not have a constructor with the name '
                    '`missing`.',
              )
              .having((e) => e.element, 'element', same(ctors)),
        ),
      );
    });
  });

  group('planConstruction', () {
    List<String?> names(List<FormalParameterElement> params) =>
        params.map((p) => p.name).toList();

    test('all names available', () {
      final plan = planConstruction(ctors.unnamedConstructor!, {'a', 'b', 'c'});
      expect(plan.constructor, same(ctors.unnamedConstructor));
      expect(names(plan.positional), ['a', 'b']);
      expect(names(plan.named), ['c']);
      expect(plan.unmatched, isEmpty);
      expect(plan.consumedNames, {'a', 'b', 'c'});
    });

    test('an unmatched positional parameter keeps its slot', () {
      final plan = planConstruction(ctors.unnamedConstructor!, {'a', 'c'});
      expect(names(plan.positional), ['a', 'b']);
      expect(names(plan.named), ['c']);
      expect(names(plan.unmatched), ['b']);
      expect(plan.consumedNames, {'a', 'c'});
    });

    test('unmatched optional positional parameters', () {
      final plan = planConstruction(ctors.getNamedConstructor('optional')!, {
        'a',
      });
      expect(names(plan.positional), ['a', 'b', 'extra']);
      expect(plan.named, isEmpty);
      expect(names(plan.unmatched), ['b', 'extra']);
      expect(plan.unmatched.map((p) => p.isOptionalPositional), [true, true]);
      expect(plan.consumedNames, {'a'});
    });

    test('unmatched named parameters are not in named', () {
      final plan = planConstruction(ctors.getNamedConstructor('named')!, {
        'a',
        'b',
        'd',
      });
      expect(names(plan.positional), ['a']);
      expect(names(plan.named), ['b', 'd']);
      expect(names(plan.unmatched), ['c']);
      expect(plan.consumedNames, {'a', 'b', 'd'});
    });

    test('unmatched required named parameters are reported', () {
      final plan = planConstruction(ctors.getNamedConstructor('named')!, {'a'});
      expect(names(plan.unmatched), ['b', 'c', 'd']);
      expect(plan.unmatched.first.isRequiredNamed, isTrue);
    });

    test('extra available names are ignored', () {
      final plan = planConstruction(ctors.unnamedConstructor!, {
        'a',
        'b',
        'c',
        'zzz',
      });
      expect(plan.consumedNames, {'a', 'b', 'c'});
    });

    test('results are unmodifiable', () {
      final plan = planConstruction(ctors.unnamedConstructor!, {'a', 'b', 'c'});
      expect(plan.positional.clear, throwsUnsupportedError);
      expect(plan.named.clear, throwsUnsupportedError);
      expect(plan.unmatched.clear, throwsUnsupportedError);
      expect(plan.consumedNames.clear, throwsUnsupportedError);
    });
  });

  group('typeParameterListCode', () {
    test('no type parameters', () {
      final plain = library.cls('Plain');
      expect(typeParameterListCode(plain, withBounds: false), '');
      expect(typeParameterListCode(plain, withBounds: true), '');
    });

    test('without bounds', () {
      expect(
        typeParameterListCode(library.cls('Generic'), withBounds: false),
        '<T, S>',
      );
    });

    test('with bounds', () {
      expect(
        typeParameterListCode(library.cls('Generic'), withBounds: true),
        '<T extends num, S>',
      );
    });

    test('nullable bound', () {
      expect(
        typeParameterListCode(library.cls('NullableBound'), withBounds: true),
        '<T extends Object?>',
      );
    });
  });
}
