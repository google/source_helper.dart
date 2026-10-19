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
import 'package:meta/meta.dart';

@experimental
extension ExecutableElementExtension on ExecutableElement {
  /// The name to use when emitting a tear-off of `this`: `fn` for a top-level
  /// function, `Class.method` for a method, and `Class` or `Class.named` for
  /// a constructor.
  ///
  /// Throws an [UnsupportedError] for any other kind of executable, such as a
  /// local function.
  String get qualifiedName {
    final self = this;

    if (self is TopLevelFunctionElement) {
      return name!;
    }

    if (self is MethodElement) {
      return '${enclosingElement!.name}.$name';
    }

    if (self is ConstructorElement) {
      // The default constructor.
      if (name == null || name!.isEmpty || name == 'new') {
        return enclosingElement!.name!;
      }
      return '${enclosingElement!.name}.$name';
    }

    throw UnsupportedError('Not sure how to support a ${kind.displayName}.');
  }
}
