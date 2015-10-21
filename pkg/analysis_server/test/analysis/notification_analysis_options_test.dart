// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test.analysis.notification.analysis_options;

import 'package:analysis_server/plugin/protocol/protocol.dart';
import 'package:analysis_server/src/constants.dart';
import 'package:analysis_server/src/domain_analysis.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/services/lint.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:unittest/unittest.dart';

import '../analysis_abstract.dart';
import '../mocks.dart';
import '../utils.dart';

main() {
  initializeTestEnvironment();
  defineReflectiveTests(AnalysisOptionsFileNotificationTest);
}

@reflectiveTest
class AnalysisOptionsFileNotificationTest extends AbstractAnalysisTest {
  /// Cached model state in case tests need to set task model to on/off.
  bool wasTaskModelEnabled;

  Map<String, List<AnalysisError>> filesErrors = {};

  final testSource = '''
main() {
  var x = '';
  int y = x; // Not assignable in strong-mode
  print(y);
}''';

  List<AnalysisError> get errors => filesErrors[testFile];

  List<AnalysisError> get optionsFileErrors => filesErrors[optionsFilePath];

  String get optionsFilePath => '$projectPath/.analysis_options';

  AnalysisContext get testContext => server.getContainingContext(testFile);

  void addOptionsFile(String contents) {
    addFile(optionsFilePath, contents);
  }

  void deleteFile(String filePath) {
    resourceProvider.deleteFile(filePath);
  }

  @override
  void processNotification(Notification notification) {
    if (notification.event == ANALYSIS_ERRORS) {
      var decoded = new AnalysisErrorsParams.fromNotification(notification);
      filesErrors[decoded.file] = decoded.errors;
    }
  }

  void setAnalysisRoot() {
    Request request =
        new AnalysisSetAnalysisRootsParams([projectPath], []).toRequest('0');
    handleSuccessfulRequest(request);
  }

  void setStrongMode(bool isSet) {
    addOptionsFile('''
analyzer:
  strong-mode: $isSet
''');
  }

  @override
  void setUp() {
    super.setUp();
    server.handlers = [new AnalysisDomainHandler(server)];
    wasTaskModelEnabled = AnalysisEngine.instance.useTaskModel;
    AnalysisEngine.instance.useTaskModel = true;
  }

  @override
  void tearDown() {
    AnalysisEngine.instance.useTaskModel = wasTaskModelEnabled;
    super.tearDown();
  }

  test_lint_options_changes() async {
    addOptionsFile('''
linter:
  rules:
    - camel_case_types
    - constant_identifier_names
''');

    addTestFile(testSource);
    setAnalysisRoot();

    await waitForTasksFinished();

    verifyLintsEnabled(['camel_case_types', 'constant_identifier_names']);

    addOptionsFile('''
linter:
  rules:
    - camel_case_types
''');

    await pumpEventQueue();
    await waitForTasksFinished();

    verifyLintsEnabled(['camel_case_types']);
  }

  test_options_file_added() async {
    addTestFile(testSource);
    setAnalysisRoot();

    await waitForTasksFinished();

    // Verify strong-mode disabled.
    verifyStrongMode(enabled: false);

    // Clear errors.
    filesErrors[testFile] = [];

    // Add options file with strong mode enabled.
    setStrongMode(true);

    await pumpEventQueue();
    await waitForTasksFinished();

    verifyStrongMode(enabled: true);
  }

  test_options_file_parse_error() async {
    addOptionsFile('''
; #bang
''');
    setAnalysisRoot();

    await waitForTasksFinished();

    expect(optionsFileErrors, hasLength(1));
    expect(optionsFileErrors.first.severity, AnalysisErrorSeverity.ERROR);
    expect(optionsFileErrors.first.type, AnalysisErrorType.COMPILE_TIME_ERROR);
  }

  test_options_file_removed() async {
    setStrongMode(true);

    addTestFile(testSource);
    setAnalysisRoot();

    await waitForTasksFinished();

    verifyStrongMode(enabled: true);

    // Clear errors.
    filesErrors[testFile] = [];

    deleteFile(optionsFilePath);

    await pumpEventQueue();
    await waitForTasksFinished();

    verifyStrongMode(enabled: false);
  }

  test_strong_mode_changed() async {
    setStrongMode(true);

    addTestFile(testSource);
    setAnalysisRoot();

    await waitForTasksFinished();

    verifyStrongMode(enabled: true);

    // Clear errors.
    filesErrors[testFile] = [];

    setStrongMode(false);

    await pumpEventQueue();
    await waitForTasksFinished();

    verifyStrongMode(enabled: false);
  }

  void verifyLintsEnabled(List<String> lints) {
    expect(testContext.analysisOptions.lint, true);
    var rules = getLints(testContext).map((rule) => rule.name);
    expect(rules, unorderedEquals(lints));
  }

  verifyStrongMode({bool enabled}) {
    // Verify strong-mode enabled.
    expect(testContext.analysisOptions.strongMode, enabled);

    if (enabled) {
      // Should produce a warning and an error.
      expect(
          errors.map((error) => error.type),
          unorderedEquals([
            AnalysisErrorType.STATIC_TYPE_WARNING,
            AnalysisErrorType.COMPILE_TIME_ERROR
          ]));
    } else {
      // Should only produce a hint.
      expect(errors.map((error) => error.type),
          unorderedEquals([AnalysisErrorType.HINT]));
    }
  }
}
