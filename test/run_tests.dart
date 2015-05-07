import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart' show AnsiPen;
import 'package:args/args.dart';


typedef String _Pen(String);

_Pen _greenPen = new AnsiPen()..green(bold: true);
_Pen _redPen = new AnsiPen()..red(bold: true);

const String testSuccessMessage = 'All tests passed!';
const String testFailureMessage = 'Some tests failed.';


class TestRunException implements Exception {}

Future waitFor(Process process, {String successPattern, String failurePattern, bool verbose: false}) {
  Completer completer = new Completer();

  void listenTo(Stream ioStream) {
    ioStream.transform(new Utf8Decoder()).transform(new LineSplitter()).listen((String line) {
      if (verbose) {
        print(line);
      }
      if (successPattern != null && line.contains(successPattern)) {
        if (!completer.isCompleted) {
          completer.complete(line);
        }
      }
      if (failurePattern != null && line.contains(failurePattern)) {
        if (!completer.isCompleted) {
          completer.completeError(line);
        }
      }
    }, onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(new TestRunException());
      }
    });
  }

  listenTo(process.stdout);
  listenTo(process.stderr);

  return completer.future;
}

void shutdown(List<Process> processesToKill) {
  processesToKill.forEach((p) {
    if (p != null) {
      p.kill(ProcessSignal.SIGINT);
    }
  });
  print('Testing failed.');
  exit(1);
}

main(List<String> args) async {
  ArgParser parser = new ArgParser()
    ..addOption('platform', abbr: 'p', allowMultiple: true)
    ..addFlag('coverage', negatable: false)
    ..addFlag('verbose', abbr: 'v', negatable: false);
  ArgResults env = parser.parse(args);

  Process server;
  Process coverage;
  Process tests;

  try {
    // Start the server (necessary for integration tests).
    server = await Process.start('dart', ['--checked', 'tool/server/run.dart', '--no-proxy']);
    await waitFor(server, successPattern: 'ready - listening', verbose: env['verbose']);

    // If generating coverage, we run the tests differently
    // TODO: Hopefully clean this up when test package adds support for coverage
    if (env['coverage']) {
      // Start the coverage run.
      List coverageArgs = ['run', 'dart_codecov_generator', '--report-on=lib/'];
      if (env['verbose']) {
        coverageArgs.add('-v');
      }
      coverage = await Process.start('pub', coverageArgs);

      // Wait for coverage to complete.
      print(await waitFor(coverage, successPattern: 'Coverage generated', failurePattern: 'failed', verbose: env['verbose']));
    } else {
      // Start the test runs.
      List testArgs = ['run', 'test'];
      if (env['platform'].length > 0) {
        testArgs.addAll((env['platform'] as List).map((p) => '--platform=$p'));
      } else {
        testArgs.addAll(['-p', 'vm', '-p', 'dartium']);
      }
      print('pub ${testArgs.join(' ')}');
      tests = await Process.start('pub', testArgs);

      // Wait for test runs to complete.
      print(await waitFor(tests, successPattern: testSuccessMessage, failurePattern: testFailureMessage, verbose: env['verbose']));
    }

    // Kill the server now that we're done.
    server.kill(ProcessSignal.SIGINT);

    // Verify success of all processes
    int serverEC = await server.exitCode;
    int coverageEC = coverage != null ? await coverage.exitCode : 0;
    int testsEC = tests != null ? await tests.exitCode : 0;

    if (serverEC > 0 || coverageEC > 0 || testsEC > 0) throw new Exception('Testing failed.');

    // Success!
    print('Success!');
    exit(0);
  } on TestRunException catch (e) {
    print('Unexpected error running tests. Try running again with -v for more info.');
    shutdown([server, coverage, tests]);
  } catch (e, stackTrace) {
    print('$e\n$stackTrace');
    shutdown([server, coverage, tests]);
  }
}