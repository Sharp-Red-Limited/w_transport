// Copyright 2015 Workiva Inc.
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

import 'dart:html';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:w_transport/browser.dart';
import 'package:w_transport/w_transport.dart' as transport;

import '../../naming.dart';
import '../integration_paths.dart';
import 'common.dart';

const _sockjsPort = 8026;

void runCommonSockJSSuite(List<String> protocolsToTest,
    {bool usingSockjsPort = true}) {
  final naming = Naming()
    ..platform = usingSockjsPort
        ? platformBrowserSockjsPort
        : platformBrowserSockjsWrapper
    ..testType = testTypeIntegration
    ..topic = topicWebSocket;

  for (final protocol in protocolsToTest) {
    group('$naming (protocol=$protocol)', () {
      connect(Uri uri, String protocol) => transport.WebSocket.connect(uri,
          transportPlatform: BrowserTransportPlatformWithSockJS(
              sockJSNoCredentials: true, sockJSProtocolsWhitelist: [protocol]));

      runCommonWebSocketIntegrationTests(
          connect: (Uri uri) => connect(uri, protocol), port: _sockjsPort);

      final echoUri = IntegrationPaths.echoUri.replace(port: _sockjsPort);
      final pingUri = IntegrationPaths.pingUri.replace(port: _sockjsPort);

      test('should not support Blob', () async {
        final blob = Blob(['one', 'two']);
        final socket = await connect(pingUri, protocol);
        expect(() {
          socket.add(blob);
        }, throwsArgumentError);
        await socket.close();
      });

      test('should support String', () async {
        const data = 'data';
        final socket = await connect(echoUri, protocol);
        socket.add(data);
        await socket.close();
      });

      test('should not support TypedData', () async {
        final data = Uint16List.fromList([1, 2, 3]);
        final socket = await connect(echoUri, protocol);
        expect(() {
          socket.add(data);
        }, throwsArgumentError);
        await socket.close();
      });

      test('should throw when attempting to send invalid data', () async {
        final socket = await connect(pingUri, protocol);
        expect(() {
          socket.add(true);
        }, throwsArgumentError);
        await socket.close();
      });
    });
  }
}
