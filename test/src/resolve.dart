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

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

/// Resolves [source] as a standalone library in a temporary directory.
///
/// Safe to call from `setUpAll`: the directory is removed by a tear-down
/// registered for the enclosing group.
Future<ResolvedLibraryResult> resolveSource(String source) async {
  final dir = Directory.systemTemp.createTempSync('source_helper_test_');
  addTearDown(() => dir.delete(recursive: true));

  const fileName = 'fixture.dart';
  await d.file(fileName, source).create(dir.path);
  final path = '${dir.path}${Platform.pathSeparator}$fileName';

  final collection = AnalysisContextCollection(includedPaths: [dir.path]);
  final result = await collection
      .contextFor(path)
      .currentSession
      .getResolvedLibrary(path);

  if (result is! ResolvedLibraryResult) {
    throw StateError('Could not resolve the fixture: $result');
  }

  final diagnostics = result.units.expand((u) => u.diagnostics).toList();
  if (diagnostics.isNotEmpty) {
    throw StateError('The fixture has diagnostics:\n${diagnostics.join('\n')}');
  }

  return result;
}

extension LibraryElementTestExtension on LibraryElement {
  /// The class named [name]; throws if there is none.
  ClassElement cls(String name) =>
      getClass(name) ?? (throw ArgumentError('No class `$name`.'));
}

extension InterfaceElementTestExtension on InterfaceElement {
  /// The field named [name]; throws if there is none.
  FieldElement field(String name) =>
      getField(name) ?? (throw ArgumentError('No field `$name` on `$this`.'));
}

extension FieldElementListTestExtension on List<FieldElement> {
  /// The names of the fields, in order.
  List<String?> get names => map((f) => f.name).toList();
}
