import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('overlay/window');
  late MethodChannelOverlayHost host;
  late List<MethodCall> calls;
  var excluded = false;
  var rejectChange = false;

  setUp(() {
    host = MethodChannelOverlayHost();
    calls = [];
    excluded = false;
    rejectChange = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'getState') {
        return {
          'topmost': true,
          'interactive': false,
          'excludedFromCapture': excluded,
        };
      }
      if (call.method == 'setExcludedFromCapture') {
        if (rejectChange) {
          throw PlatformException(code: 'DISPLAY_AFFINITY_FAILED', details: 87);
        }
        excluded = call.arguments as bool;
      }
      return null;
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test('startup restores capture exclusion once before completing', () async {
    await host.initialize(excludedFromCapture: true);
    expect(excluded, isTrue);
    expect(host.state.excludedFromCapture, isTrue);
    await host.initialize(excludedFromCapture: true);
    expect(calls.map((call) => call.method), [
      'getState',
      'setExcludedFromCapture',
    ]);
    await host.setInteractive(true);
    await host.setTopmost(false);
    expect(host.state.excludedFromCapture, isTrue);
    expect(host.state.interactive, isTrue);
    expect(host.state.topmost, isFalse);
    await host.setExcludedFromCapture(false);
    expect(excluded, isFalse);
    expect(host.state.excludedFromCapture, isFalse);
    expect(host.state.interactive, isTrue);
  });

  test('default startup leaves capture enabled normally', () async {
    await host.initialize();
    expect(host.state.excludedFromCapture, isFalse);
    expect(calls.map((call) => call.method), ['getState']);
  });

  test('failed native changes preserve the last confirmed state', () async {
    await host.initialize(excludedFromCapture: true);
    rejectChange = true;
    await expectLater(
      host.setExcludedFromCapture(false),
      throwsA(isA<PlatformException>()),
    );
    expect(host.state.excludedFromCapture, isTrue);
    expect(excluded, isTrue);
    rejectChange = false;
    await host.setExcludedFromCapture(false);
    expect(host.state.excludedFromCapture, isFalse);
  });

  test('failed startup can be retried through the setting', () async {
    rejectChange = true;
    await expectLater(
      host.initialize(excludedFromCapture: true),
      throwsA(isA<PlatformException>()),
    );
    expect(host.state.excludedFromCapture, isFalse);
    rejectChange = false;
    await host.setExcludedFromCapture(true);
    expect(host.state.excludedFromCapture, isTrue);
  });
}
