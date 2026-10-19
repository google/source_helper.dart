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
class Tag {
  final String value;
  const Tag(this.value);
}

class Base {
  int baseField = 0;

  final int? nullableBase;

  int get baseGetter => 1;

  set baseSetterOnly(int value) {}

  Base(this.nullableBase);

  @override
  int get hashCode => 0;

  @override
  bool operator ==(Object other) => identical(this, other);
}

class Middle extends Base {
  String middleField = '';

  Middle(super.nullableBase);
}

class Sub extends Middle {
  bool subField = false;

  @override
  int get baseGetter => 2;

  Sub(super.nullableBase);
}

class Unrelated {
  int other = 0;
}

abstract class HasId {
  int get id;
}

abstract class Entity implements HasId {
  String label = '';
}

class Narrow {
  num get n => 1;
}

class Narrower extends Narrow {
  @override
  int get n => 2;
}

class SetterOverride extends Narrow {
  set n(num value) {}
}

class Box<T> {
  T item;

  Box(this.item);
}

class IntBox extends Box<int> {
  int extra = 0;

  IntBox(super.item);
}

mixin Mixed {
  int mixed = 0;
}

class WithMixin with Mixed {
  int own = 1;
}

class AnnBase {
  @Tag('base field')
  int f1 = 0;

  int get f2 => 1;

  @Tag('base getter')
  int get f3 => 1;

  set f4(int value) {}

  @Tag('base setter')
  set f5(int value) {}

  @Tag('own field')
  int f6 = 0;
}

class AnnSub extends AnnBase {
  @override
  int f1 = 1;

  @Tag('sub getter')
  @override
  int get f2 => 2;

  @override
  int get f3 => 3;

  @Tag('sub field')
  @override
  int f6 = 1;
}

abstract class AbsBase {
  @Tag('abs base')
  int get x;
}

class ConcreteSub extends AbsBase {
  @override
  int get x => 1;
}

class Grand {
  @Tag('grand')
  int get x => 1;
}

abstract class AbsMid extends Grand {
  @Tag('mid')
  @override
  int get x;
}

class LeafSub extends AbsMid {
  @override
  int get x => 2;
}

class LeafSubInherited extends AbsMid {}

class MixBase {
  @Tag('mix base')
  int get x => 1;
}

mixin MixOnTop {
  @Tag('mix on top')
  int get x => 2;
}

class MixParent extends MixBase with MixOnTop {
  @override
  int get x => 3;
}

class MixChild extends MixParent {
  @override
  int get x => 4;
}

abstract class Iface {
  @Tag('iface')
  int get x;
}

class SuperWithX {
  int get x => 1;
}

class SubAndIface extends SuperWithX implements Iface {
  @override
  int get x => 2;
}

class OnlyIface implements Iface {
  @override
  int get x => 2;
}

mixin OrderMixin {
  int mixinField = 0;
}

class OrderSub extends OrderBase with OrderMixin {
  int subField = 0;
}

class OrderBase {
  int baseField = 0;
}
''';

const _tagChecker = TypeChecker.typeNamedLiterally('Tag');

void main() {
  late LibraryElement library;
  ClassElement cls(String name) => library.cls(name);

  setUpAll(() async {
    library = (await resolveSource(_source)).element;
  });

  group('createSortedFieldSet', () {
    test('superclass fields first, then declaration order', () {
      expect(createSortedFieldSet(cls('Sub')).names, [
        'baseField',
        'nullableBase',
        'middleField',
        'subField',
        'baseGetter',
      ]);
    });

    test('an overridden member sorts at its subclass position', () {
      final fields = createSortedFieldSet(cls('Sub'));
      final baseGetter = fields.singleWhere((f) => f.name == 'baseGetter');
      expect(baseGetter.enclosingElement.name, 'Sub');
    });

    test('a getter-defined property sorts by its getter offset', () {
      expect(createSortedFieldSet(cls('Base')).names, [
        'baseField',
        'nullableBase',
        'baseGetter',
        'baseSetterOnly',
      ]);
    });

    test('an inherited setter-only property is dropped by default', () {
      expect(
        createSortedFieldSet(cls('Sub')).names,
        isNot(contains('baseSetterOnly')),
      );
    });

    test(
      'an inherited setter-only property is kept with includeSetterOnly',
      () {
        final fields = createSortedFieldSet(
          cls('Sub'),
          includeSetterOnly: true,
        );
        expect(fields.names, contains('baseSetterOnly'));
        final setterOnly = fields.singleWhere(
          (f) => f.name == 'baseSetterOnly',
        );
        expect(setterOnly.getter, isNull);
        expect(setterOnly.setter, isNotNull);
      },
    );

    test('hashCode and runtimeType overrides are dropped by default', () {
      expect(
        createSortedFieldSet(cls('Base')).names,
        isNot(contains('hashCode')),
      );
      expect(
        createSortedFieldSet(cls('Sub')).names,
        isNot(contains('hashCode')),
      );
    });

    test('keepObjectMemberOverride keeps them', () {
      final seen = <String?>[];
      final fields = createSortedFieldSet(
        cls('Sub'),
        keepObjectMemberOverride: (f) {
          seen.add(f.name);
          return true;
        },
      );
      expect(fields.names, contains('hashCode'));
      expect(seen, everyElement('hashCode'));
    });

    test('concrete scope omits abstract interface members', () {
      expect(createSortedFieldSet(cls('Entity')).names, ['label']);
    });

    test('all scope includes abstract interface members', () {
      expect(
        createSortedFieldSet(
          cls('Entity'),
          scope: InheritedMemberScope.all,
        ).names,
        ['id', 'label'],
      );
    });

    test('a narrowed getter override wins', () {
      final fields = createSortedFieldSet(cls('Narrower'));
      expect(fields.names, ['n']);
      expect(fields.single.type.getDisplayString(), 'int');
      expect(fields.single.enclosingElement.name, 'Narrower');
    });

    test('a setter-only override keeps the inherited getter field', () {
      final fields = createSortedFieldSet(cls('SetterOverride'));
      expect(fields.names, ['n']);
      expect(fields.single.enclosingElement.name, 'Narrow');
      expect(fields.single.getter, isNotNull);
    });

    test('generic superclass fields', () {
      final fields = createSortedFieldSet(cls('IntBox'));
      expect(fields.names, ['item', 'extra']);
      expect(fields.first.enclosingElement.name, 'Box');
      expect(fields.first.type.getDisplayString(), 'int');
      expect(
        fieldOverrideChain(
          cls('IntBox'),
          fields.first,
        ).map((f) => f.enclosingElement.name),
        ['Box'],
      );
    });

    test('mixin fields', () {
      expect(createSortedFieldSet(cls('WithMixin')).names, ['mixed', 'own']);
    });

    test('static fields are excluded', () {
      expect(createSortedFieldSet(cls('Tag')).names, ['value']);
    });

    test('transitive hierarchy order across superclass and mixin', () {
      expect(createSortedFieldSet(cls('OrderSub')).names, [
        'baseField',
        'mixinField',
        'subField',
      ]);
    });
  });

  group('fieldOverrideChain', () {
    test('overridden member: subclass first, then supertypes', () {
      final sub = cls('Sub');
      final chain = fieldOverrideChain(sub, sub.field('baseGetter'));
      expect(chain.names, ['baseGetter', 'baseGetter']);
      expect(chain.map((f) => f.enclosingElement.name), ['Sub', 'Base']);
    });

    test('includes abstract superclass declaration overridden in subclass', () {
      final sub = cls('ConcreteSub');
      final chain = fieldOverrideChain(sub, sub.field('x'));
      expect(chain.map((f) => f.enclosingElement.name), [
        'ConcreteSub',
        'AbsBase',
      ]);
    });

    test(
      'orders abstract intermediate override before concrete grandparent',
      () {
        final sub = cls('LeafSub');
        final chain = fieldOverrideChain(sub, sub.field('x'));
        expect(chain.map((f) => f.enclosingElement.name), [
          'LeafSub',
          'AbsMid',
          'Grand',
        ]);
      },
    );

    test('orders mixin on parent before parent superclass', () {
      final child = cls('MixChild');
      final chain = fieldOverrideChain(child, child.field('x'));
      expect(chain.map((f) => f.enclosingElement.name), [
        'MixChild',
        'MixParent',
        'MixOnTop',
        'MixBase',
      ]);
    });

    test('excludes implemented interfaces from concrete override chain', () {
      final subAndIface = cls('SubAndIface');
      expect(
        fieldOverrideChain(
          subAndIface,
          subAndIface.field('x'),
        ).map((f) => f.enclosingElement.name),
        ['SubAndIface', 'SuperWithX'],
      );

      final onlyIface = cls('OnlyIface');
      expect(
        fieldOverrideChain(
          onlyIface,
          onlyIface.field('x'),
        ).map((f) => f.enclosingElement.name),
        ['OnlyIface'],
      );
    });

    test('is the same chain from any member of it', () {
      final sub = cls('Sub');
      final fromSub = fieldOverrideChain(sub, sub.field('baseGetter'));
      final fromBase = fieldOverrideChain(sub, cls('Base').field('baseGetter'));
      expect(fromBase, fromSub);
    });

    test('inherited member without override', () {
      final chain = fieldOverrideChain(
        cls('Sub'),
        cls('Base').field('baseField'),
      );
      expect(chain.map((f) => f.enclosingElement.name), ['Base']);
    });

    test('setter-only override chain keeps both declarations', () {
      final chain = fieldOverrideChain(
        cls('SetterOverride'),
        cls('Narrow').field('n'),
      );
      expect(chain.map((f) => f.enclosingElement.name), [
        'SetterOverride',
        'Narrow',
      ]);
    });

    test('a field outside the hierarchy returns itself', () {
      final other = cls('Unrelated').field('other');
      expect(fieldOverrideChain(cls('Sub'), other), [other]);
    });

    test('does not drop hashCode overrides', () {
      final sub = cls('Sub');
      final hashCode = cls('Base').field('hashCode');
      expect(fieldOverrideChain(sub, hashCode), [hashCode]);
    });
  });

  group('firstAnnotationOnProperty', () {
    String? tag(String className, String name) => firstAnnotationOnProperty(
      cls(className),
      name,
      _tagChecker,
    )?.getField('value')?.toStringValue();

    test('own field annotation', () {
      expect(tag('AnnBase', 'f1'), 'base field');
      expect(tag('AnnBase', 'f6'), 'own field');
    });

    test('own getter annotation', () {
      expect(tag('AnnBase', 'f3'), 'base getter');
    });

    test('subclass field annotation wins over the superclass', () {
      expect(tag('AnnSub', 'f6'), 'sub field');
    });

    test('unannotated subclass field falls back to the superclass field', () {
      expect(tag('AnnSub', 'f1'), 'base field');
    });

    test('subclass getter annotation', () {
      expect(tag('AnnSub', 'f2'), 'sub getter');
    });

    test('unannotated subclass getter falls back to the superclass getter', () {
      expect(tag('AnnSub', 'f3'), 'base getter');
    });

    test('inherited setter-only property does not crash', () {
      expect(tag('AnnSub', 'f4'), isNull);
    });

    test('setter annotations are not consulted', () {
      expect(tag('AnnBase', 'f5'), isNull);
      expect(tag('AnnSub', 'f5'), isNull);
    });

    test('unknown property', () {
      expect(tag('AnnSub', 'nope'), isNull);
    });

    test('unannotated property', () {
      expect(tag('AnnBase', 'f2'), isNull);
    });

    test('falls back to abstract superclass getter annotation', () {
      expect(tag('ConcreteSub', 'x'), 'abs base');
    });

    test(
      'prefers abstract intermediate override annotation over grandparent',
      () {
        expect(tag('LeafSub', 'x'), 'mid');
        expect(tag('LeafSubInherited', 'x'), 'mid');
      },
    );

    test('prefers mixin annotation on parent over parent superclass', () {
      expect(tag('MixParent', 'x'), 'mix on top');
      expect(tag('MixChild', 'x'), 'mix on top');
    });

    test('ignores annotations on implemented interfaces', () {
      expect(tag('SubAndIface', 'x'), isNull);
      expect(tag('OnlyIface', 'x'), isNull);
    });
  });
}
