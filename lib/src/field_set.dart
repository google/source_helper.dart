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

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';

const _objectMemberNames = {'hashCode', 'runtimeType'};

const _dartCoreObjectChecker = TypeChecker.typeNamed(
  Object,
  inPackage: 'core',
  inSdk: true,
);

/// Which inherited members [createSortedFieldSet] considers.
enum InheritedMemberScope {
  /// Members inherited from the superclass chain and mixins, via
  /// `InterfaceElement.inheritedConcreteMembers`.
  concrete,

  /// Every inherited member, including abstract ones declared by interfaces,
  /// via `InterfaceElement.inheritedMembers`.
  all,
}

/// Returns all instance [FieldElement]s of [element] and its supertypes,
/// one per name, sorted first by position in the inheritance hierarchy
/// (supertypes first) and then by position in the source file.
///
/// Inherited members are collected according to [scope]. Inherited properties
/// that only have a setter are ignored unless [includeSetterOnly] is `true`.
///
/// Overrides of `Object.hashCode` and `Object.runtimeType` are dropped unless
/// [keepObjectMemberOverride] returns `true` for them.
///
/// When a name is declared more than once in the hierarchy, the returned
/// [FieldElement] is the first one in the [fieldOverrideChain] that has a
/// getter, so a narrowed subclass type wins while a setter-only subclass
/// override keeps the inherited getter's field.
List<FieldElement> createSortedFieldSet(
  InterfaceElement element, {
  InheritedMemberScope scope = InheritedMemberScope.concrete,
  bool includeSetterOnly = false,
  bool Function(FieldElement objectMemberOverride)? keepObjectMemberOverride,
}) {
  final chains = _overrideChains(
    element,
    scope: scope,
    includeSetterOnly: includeSetterOnly,
    keepObjectMemberOverride: keepObjectMemberOverride ?? _dropObjectMembers,
  );

  final fieldSets = chains.values.map(_FieldSet.new).toList()..sort();

  return fieldSets.map((fs) => fs.field).toList(growable: false);
}

/// Returns the override chain of the property named `field.name` in
/// [element]: the declaration in [element], if any, followed by the overridden
/// supertype declarations in inheritance order.
///
/// Inherited members are resolved as [createSortedFieldSet] does with its
/// default [InheritedMemberScope.concrete] scope. Returns `[field]` when
/// [field] is not part of that chain.
///
/// A pure function of the element model.
List<FieldElement> fieldOverrideChain(
  InterfaceElement element,
  FieldElement field,
) {
  final chain = _overrideChains(
    element,
    scope: InheritedMemberScope.concrete,
    includeSetterOnly: false,
    keepObjectMemberOverride: _keepAll,
  )[field.name];

  if (chain == null || !chain.contains(field)) {
    return [field];
  }
  return chain;
}

/// Returns the first annotation matching [checker] on the property named
/// [name] in [element], or `null` if there is none.
///
/// Each [FieldElement] in the [fieldOverrideChain] of the property is checked
/// in order: the field itself first, then its getter if it has one. Properties
/// declared only by a getter or only by a setter are handled; the property is
/// looked up by name so no [FieldElement] is needed up front.
DartObject? firstAnnotationOnProperty(
  InterfaceElement element,
  String name,
  TypeChecker checker,
) {
  final chain = _overrideChains(
    element,
    scope: InheritedMemberScope.concrete,
    includeSetterOnly: true,
    keepObjectMemberOverride: _keepAll,
  )[name];

  if (chain == null) {
    return null;
  }

  for (final candidate in chain) {
    final annotation =
        checker.firstAnnotationOf(candidate) ??
        switch (candidate.getter) {
          null => null,
          final getter => checker.firstAnnotationOf(getter),
        };
    if (annotation != null) {
      return annotation;
    }
  }
  return null;
}

bool _dropObjectMembers(FieldElement _) => false;

bool _keepAll(FieldElement _) => true;

/// Maps each instance property name of [element] to its override chain: the
/// field declared on [element], if any, followed by the overridden supertype
/// fields in inheritance order.
Map<String?, List<FieldElement>> _overrideChains(
  InterfaceElement element, {
  required InheritedMemberScope scope,
  required bool includeSetterOnly,
  required bool Function(FieldElement) keepObjectMemberOverride,
}) {
  bool isDroppedObjectMember(FieldElement e) =>
      _objectMemberNames.contains(e.name) && !keepObjectMemberOverride(e);

  final elementInstanceFields = Map.fromEntries(
    element.fields
        .where((e) => !e.isStatic && !isDroppedObjectMember(e))
        .map((e) => MapEntry(e.name, e)),
  );

  final inheritedFields = <String, List<FieldElement>>{};

  final inheritedMembers = switch (scope) {
    InheritedMemberScope.concrete => element.inheritedConcreteMembers,
    InheritedMemberScope.all => element.inheritedMembers,
  };

  for (final member in inheritedMembers.values) {
    if (_dartCoreObjectChecker.isExactly(member.enclosingElement!)) {
      continue;
    }

    final FieldElement variable;
    switch (member) {
      case GetterElement(variable: final FieldElement v):
        variable = v;
      case SetterElement(variable: final FieldElement v) when includeSetterOnly:
        variable = v;
      default:
        continue;
    }

    if (isDroppedObjectMember(variable)) {
      continue;
    }
    final list = inheritedFields.putIfAbsent(variable.name!, () => []);
    if (!list.contains(variable)) {
      list.add(variable);
    }
  }

  for (final supertype in element.allSupertypes) {
    if (_dartCoreObjectChecker.isExactly(supertype.element)) {
      continue;
    }
    for (final field in supertype.element.fields) {
      if (field.isStatic || isDroppedObjectMember(field)) {
        continue;
      }
      final name = field.name;
      if (name == null) {
        continue;
      }
      final list = inheritedFields[name];
      if (list != null && !list.contains(field)) {
        list.add(field);
      }
    }
  }

  final allNames = elementInstanceFields.keys.toSet().union(
    inheritedFields.keys.toSet(),
  );

  return {
    for (final name in allNames)
      // At least one of these is non-null, perhaps both.
      name: <FieldElement>[
        ?elementInstanceFields[name],
        ...?inheritedFields[name],
      ],
  };
}

class _FieldSet implements Comparable<_FieldSet> {
  final FieldElement field;
  final FieldElement sortField;

  _FieldSet._(this.field, this.sortField)
    : assert(field.name == sortField.name);

  /// [chain] is a non-empty override chain as produced by [_overrideChains].
  factory _FieldSet(List<FieldElement> chain) {
    // Prefer the class field over the inherited field when sorting.
    final sortField = chain.first;

    // Use the concrete field that provides the getter (so narrowed subclass
    // types win while setter-only subclass overrides keep the inherited
    // getter's FieldElement).
    final primaryField = chain.firstWhere(
      (f) => f.getter != null,
      orElse: () => chain.first,
    );

    return _FieldSet._(primaryField, sortField);
  }

  @override
  int compareTo(_FieldSet other) => _sortByLocation(sortField, other.sortField);

  static int _sortByLocation(FieldElement a, FieldElement b) {
    final checkerA = TypeChecker.fromStatic(a.enclosingElement.thisType);

    if (!checkerA.isExactly(b.enclosingElement)) {
      // In this case, prioritize the enclosingElement that is more "super".
      if (checkerA.isAssignableFrom(b.enclosingElement)) {
        return -1;
      }

      final checkerB = TypeChecker.fromStatic(b.enclosingElement.thisType);

      if (checkerB.isAssignableFrom(a.enclosingElement)) {
        return 1;
      }
    }

    return _offsetFor(a).compareTo(_offsetFor(b));
  }

  /// Returns the offset of the given field/property in its source file, with
  /// a preference for the getter if it is defined.
  static int _offsetFor(FieldElement e) {
    if (e.isOriginGetterSetter) {
      return (e.getter ?? e.setter)!.firstFragment.nameOffset ?? 0;
    }
    if (e.isOriginDeclaringFormalParameter) {
      final offset = e.declaringFormalParameter?.firstFragment.nameOffset;
      if (offset != null) {
        return offset;
      }
    }
    return e.firstFragment.nameOffset ?? 0;
  }
}
