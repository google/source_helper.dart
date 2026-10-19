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

import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';

/// Returns the constructor of [element] named [name]; `''` selects the
/// unnamed constructor.
///
/// Throws an [InvalidGenerationSourceError] if no such constructor exists.
ConstructorElement constructorByName(InterfaceElement element, String name) {
  final className = element.name;

  if (name.isEmpty) {
    final ctor = element.unnamedConstructor;
    if (ctor == null) {
      throw InvalidGenerationSourceError(
        'The class `$className` has no default constructor.',
        element: element,
      );
    }
    return ctor;
  }

  final ctor = element.getNamedConstructor(name);
  if (ctor == null) {
    throw InvalidGenerationSourceError(
      'The class `$className` does not have a constructor with the name '
      '`$name`.',
      element: element,
    );
  }
  return ctor;
}

/// How to invoke [constructor] given a set of available argument names.
///
/// Produced by [planConstruction].
final class ConstructorPlan {
  /// The constructor that was planned.
  final ConstructorElement constructor;

  /// Every positional parameter, matched or not, in declaration order.
  final List<FormalParameterElement> positional;

  /// Matched named parameters, in declaration order.
  final List<FormalParameterElement> named;

  /// Parameters whose name was not available, in declaration order.
  ///
  /// Positional ones are also present in [positional] so a renderer cannot
  /// shift later arguments into their slot.
  final List<FormalParameterElement> unmatched;

  /// The names consumed by the matched entries of [positional] and [named].
  ///
  /// Callers subtract this from their own writable set to find the members
  /// still to be assigned after construction.
  final Set<String> consumedNames;

  ConstructorPlan._({
    required this.constructor,
    required this.positional,
    required this.named,
    required this.unmatched,
    required this.consumedNames,
  });
}

/// Matches the formal parameters of [constructor] against [availableNames]
/// by name, in declaration order.
///
/// Makes no decision about unmatched parameters: callers inspect
/// [ConstructorPlan.unmatched] and apply their own policy.
ConstructorPlan planConstruction(
  ConstructorElement constructor,
  Set<String> availableNames,
) {
  final positional = <FormalParameterElement>[];
  final named = <FormalParameterElement>[];
  final unmatched = <FormalParameterElement>[];
  final consumedNames = <String>{};

  for (final param in constructor.formalParameters) {
    final name = param.name;
    final matched = name != null && availableNames.contains(name);

    if (param.isPositional) {
      positional.add(param);
    }
    if (!matched) {
      unmatched.add(param);
      continue;
    }
    if (param.isNamed) {
      named.add(param);
    }
    consumedNames.add(name);
  }

  return ConstructorPlan._(
    constructor: constructor,
    positional: List.unmodifiable(positional),
    named: List.unmodifiable(named),
    unmatched: List.unmodifiable(unmatched),
    consumedNames: Set.unmodifiable(consumedNames),
  );
}

/// Returns the type parameter list of [element] as Dart source: `<T, S>` or,
/// with [withBounds], `<T extends num, S>`.
///
/// Returns `''` when [element] has no type parameters.
String typeParameterListCode(
  InterfaceElement element, {
  required bool withBounds,
}) {
  if (element.typeParameters.isEmpty) {
    return '';
  }

  final values = element.typeParameters
      .map((t) {
        final bound = t.bound;
        if (withBounds && bound != null) {
          return '${t.name!} extends ${bound.getDisplayString()}';
        }
        return t.name!;
      })
      .join(', ');
  return '<$values>';
}
