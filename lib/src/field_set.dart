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
import 'package:analyzer/dart/element/type.dart';
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
  final hierarchy = _hierarchy(element, scope: scope);
  final rankByType = <InterfaceElement, int>{
    for (var i = 0; i < hierarchy.length; i++) hierarchy[i].element: i,
  };
  final chains = _overrideChains(
    element,
    hierarchy: hierarchy,
    scope: scope,
    includeSetterOnly: includeSetterOnly,
    keepObjectMemberOverride: keepObjectMemberOverride ?? _dropObjectMembers,
  );

  final fieldSets =
      chains.values
          .map(
            (chain) => _FieldSet(
              chain,
              rankByType[chain.first.enclosingElement as InterfaceElement]!,
            ),
          )
          .toList()
        ..sort();

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
  const scope = InheritedMemberScope.concrete;
  final chain = _overrideChains(
    element,
    hierarchy: _hierarchy(element, scope: scope),
    scope: scope,
    includeSetterOnly: false,
    keepObjectMemberOverride: _keepAll,
  )[field.name];

  if (chain == null || !chain.any((f) => f.baseElement == field.baseElement)) {
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
  const scope = InheritedMemberScope.concrete;
  final chain = _overrideChains(
    element,
    hierarchy: _hierarchy(element, scope: scope),
    scope: scope,
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

/// Returns `element.thisType` followed by its supertypes in linearized
/// override order (most-specific to least-specific), excluding `dart:core`
/// `Object`.
///
/// Using [InterfaceType] preserves type argument substitutions from [element]
/// along the superclass, mixin, and interface hierarchy.
///
/// For [InheritedMemberScope.concrete], only the superclass chain and mixins
/// applied along it are included. For [InheritedMemberScope.all], any
/// remaining [InterfaceElement.allSupertypes] (such as implemented interfaces)
/// are appended after the superclass and mixin chain.
List<InterfaceType> _hierarchy(
  InterfaceElement element, {
  required InheritedMemberScope scope,
}) {
  final result = <InterfaceType>[];
  final seen = <InterfaceElement>{};
  void add(InterfaceType type) {
    if (!type.isDartCoreObject && seen.add(type.element)) {
      result.add(type);
    }
  }

  for (
    InterfaceType? current = element.thisType;
    current != null && !current.isDartCoreObject;
    current = current.superclass
  ) {
    add(current);
    for (final mixin in current.mixins.reversed) {
      add(mixin);
    }
  }

  if (scope == InheritedMemberScope.all) {
    for (final supertype in element.allSupertypes) {
      add(supertype);
    }
  }

  return result;
}

/// Yields the instance [FieldElement]s of [type], with type parameters
/// substituted when [type] is a parameterized supertype of [origin].
Iterable<FieldElement> _fieldsOf(
  InterfaceType type, {
  required InterfaceElement origin,
}) sync* {
  if (identical(type.element, origin) || type.typeArguments.isEmpty) {
    for (final field in type.element.fields) {
      if (!field.isStatic) {
        yield field;
      }
    }
    return;
  }

  final seenNames = <String>{};
  for (final accessor in [...type.getters, ...type.setters]) {
    if (accessor.isStatic) {
      continue;
    }
    final variable = accessor.variable;
    if (variable is FieldElement &&
        variable.name != null &&
        seenNames.add(variable.name!)) {
      yield variable;
    }
  }
}

/// Maps each instance property name of [element] to its override chain: the
/// field declared on [element], if any, followed by the overridden supertype
/// fields in inheritance order.
Map<String?, List<FieldElement>> _overrideChains(
  InterfaceElement element, {
  required List<InterfaceType> hierarchy,
  required InheritedMemberScope scope,
  required bool includeSetterOnly,
  required bool Function(FieldElement) keepObjectMemberOverride,
}) {
  bool isDroppedObjectMember(FieldElement e) =>
      _objectMemberNames.contains(e.name) && !keepObjectMemberOverride(e);

  final includedNames = <String>{
    for (final field in element.fields)
      if (!field.isStatic &&
          field.name != null &&
          !isDroppedObjectMember(field))
        field.name!,
  };

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

    if (!isDroppedObjectMember(variable) && variable.name != null) {
      includedNames.add(variable.name!);
    }
  }

  final chains = <String?, List<FieldElement>>{};
  for (final type in hierarchy) {
    for (final field in _fieldsOf(type, origin: element)) {
      final name = field.name;
      if (name == null ||
          !includedNames.contains(name) ||
          isDroppedObjectMember(field)) {
        continue;
      }
      chains.putIfAbsent(name, () => []).add(field);
    }
  }

  return chains;
}

class _FieldSet implements Comparable<_FieldSet> {
  final FieldElement field;
  final FieldElement sortField;

  /// Index of `sortField.enclosingElement` in [_hierarchy] (0 is the class
  /// itself; larger indices are more-super declarations).
  final int hierarchyIndex;

  _FieldSet._(this.field, this.sortField, this.hierarchyIndex)
    : assert(field.name == sortField.name);

  /// [chain] is a non-empty override chain as produced by [_overrideChains].
  factory _FieldSet(List<FieldElement> chain, int hierarchyIndex) {
    // Prefer the class field over the inherited field when sorting.
    final sortField = chain.first;

    // Use the concrete field that provides the getter (so narrowed subclass
    // types win while setter-only subclass overrides keep the inherited
    // getter's FieldElement).
    final primaryField = chain.firstWhere(
      (f) => f.getter != null,
      orElse: () => chain.first,
    );

    return _FieldSet._(primaryField, sortField, hierarchyIndex);
  }

  @override
  int compareTo(_FieldSet other) {
    // Supertypes have a larger hierarchyIndex and sort before subtypes.
    final byType = other.hierarchyIndex.compareTo(hierarchyIndex);
    if (byType != 0) {
      return byType;
    }
    return _offsetFor(sortField).compareTo(_offsetFor(other.sortField));
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
