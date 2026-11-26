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
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

/// Returns Dart source for [type] that is valid inside [library], including
/// in its `part` files.
///
/// A class, enum, mixin, extension type or type alias that [library] imports
/// with a prefix is written with that prefix: `prefix.Name`.
///
/// A type alias is written by name when [library] can refer to it. Otherwise
/// the aliased type is written instead, which is what happens for a private
/// alias, or one that is not imported, on an inherited member.
///
/// A declaration that [library] cannot refer to at all is written with its
/// bare name.
String typeToSource(DartType type, {required LibraryElement library}) =>
    _TypeWriter(library).write(type);

final class _TypeWriter {
  final LibraryElement _library;

  _TypeWriter(this._library);

  String write(DartType type) {
    if (type.alias case final alias?) {
      if (_reference(alias.element) case final name?) {
        final unaliased = alias.element.instantiate(
          typeArguments: alias.typeArguments,
          nullabilitySuffix: NullabilitySuffix.none,
        );
        final suffix =
            type.nullabilitySuffix == NullabilitySuffix.question &&
                unaliased.nullabilitySuffix != NullabilitySuffix.question
            ? '?'
            : '';
        return '$name${_typeArguments(alias.typeArguments)}$suffix';
      }
    }
    return switch (type) {
      InterfaceType() =>
        '${_reference(type.element) ?? type.element.name}'
            '${_typeArguments(type.typeArguments)}'
            '${_suffix(type.nullabilitySuffix)}',
      TypeParameterType() =>
        '${type.element.name}${_suffix(type.nullabilitySuffix)}',
      RecordType() => _record(type),
      FunctionType() => _function(type),
      _ => type.getDisplayString(),
    };
  }

  /// How [_library] refers to [element]: `Name`, `prefix.Name`, or `null` if
  /// it cannot.
  String? _reference(Element element) {
    if (element.name case final name?) {
      final fragment = _library.firstFragment;
      if (fragment.scope.lookup(name).getter == element) {
        return name;
      }
      for (final prefix in fragment.prefixes) {
        if (prefix.scope.lookup(name).getter == element) {
          return '${prefix.name}.$name';
        }
      }
    }
    return null;
  }

  String _typeArguments(List<DartType> arguments) =>
      arguments.isEmpty ? '' : '<${arguments.map(write).join(', ')}>';

  String _suffix(NullabilitySuffix suffix) =>
      suffix == NullabilitySuffix.question ? '?' : '';

  String _record(RecordType type) {
    final positional = type.positionalFields.map((f) => write(f.type));
    final named = type.namedFields.map((f) => '${write(f.type)} ${f.name}');
    final parts = [
      ...positional,
      if (named.isNotEmpty) '{${named.join(', ')}}',
    ];
    final trailingComma =
        type.positionalFields.length == 1 && type.namedFields.isEmpty
        ? ','
        : '';
    return '(${parts.join(', ')}$trailingComma)'
        '${_suffix(type.nullabilitySuffix)}';
  }

  String _function(FunctionType type) {
    final typeParameters = type.typeParameters.map(
      (p) => switch (p.bound) {
        null => p.name!,
        final bound => '${p.name!} extends ${write(bound)}',
      },
    );
    final parameters = type.formalParameters;
    final required = parameters
        .where((p) => p.isRequiredPositional)
        .map((p) => write(p.type));
    final optional = parameters
        .where((p) => p.isOptionalPositional)
        .map((p) => write(p.type));
    final named = parameters
        .where((p) => p.isNamed)
        .map(
          (p) =>
              '${p.isRequiredNamed ? 'required ' : ''}'
              '${write(p.type)} ${p.name!}',
        );
    final parts = [
      ...required,
      if (optional.isNotEmpty) '[${optional.join(', ')}]',
      if (named.isNotEmpty) '{${named.join(', ')}}',
    ];
    return '${write(type.returnType)} Function'
        '${typeParameters.isEmpty ? '' : '<${typeParameters.join(', ')}>'}'
        '(${parts.join(', ')})${_suffix(type.nullabilitySuffix)}';
  }
}
