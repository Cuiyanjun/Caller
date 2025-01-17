library caller;

import 'dart:ui';

import 'package:caller/src/caller_event.dart';
import 'package:caller/src/failures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'src/caller_handler.dart';
export 'src/caller_event.dart';
export 'src/failures.dart';

// https://medium.com/flutter/executing-dart-in-the-background-with-flutter-plugins-and-geofencing-2b3e40a1a124
class Caller {
  static const MethodChannel _channel =
      const MethodChannel('me.leoletto.caller');

  /// Register the given callback to be called by the Caller Service
  /// even when the app is on background / closed, since each OS Handles
  /// background services in a different way, there's no guarantee that this callback
  /// will be called immediately after the Phone Call State changes, or be called at all
  ///
  /// An event callback should be a top level function or static function in order
  /// to be called by our callback dispatcher.
  ///
  /// The duration argument represents the number of seconds of the last call and
  /// will only have a value when the CallerEvent enum is equal to CallerEvent.callEnded
  /// otherwise it will be null
  ///
  /// ```dart
  /// void onEventCallback(CallerEvent event, String number, int? duration){
  ///   print('Event name: $event from number $number and possible duration $duration');
  /// }
  ///
  /// void main(){
  ///   /// Initialize the plugin and register the callback
  ///   Caller.initialize(onEventCallback);
  /// }
  /// ```
  /// {@end-tool}
  static Future<void> initialize(
    Function(CallerEvent, String, int?) onEventCallbackDispatcher,
  ) async {
    final hasPermissions = await Caller.checkPermission();

    if (!hasPermissions) throw MissingAuthorizationFailure();

    final callback = PluginUtilities.getCallbackHandle(_callbackDispatcher);
    final onEventCallback =
        PluginUtilities.getCallbackHandle(onEventCallbackDispatcher);

    try {
      await _channel.invokeMethod('initialize', <dynamic>[
        callback!.toRawHandle(),
        onEventCallback!.toRawHandle(),
      ]);
    } on PlatformException catch (_) {
      throw UnableToInitializeFailure('Unable to initialize Caller plugin');
    }
  }

  /// Prompt the user to grant permission for the events needed for this plugin
  /// to work, `READ_PHONE_STATE` and `READ_CALL_LOG`
  static Future<void> requestPermissions() async {
    await _channel.invokeMethod('requestPermissions');
  }

  /// Check if the user has granted permission for `READ_PHONE_STATE` and `READ_CALL_LOG`
  ///
  /// The future will always be resolved with a value, there's no need to wrap
  /// this method in a `try/catch` block
  static Future<bool> checkPermission() async {
    try {
      final res = await _channel.invokeMethod('checkPermissions');
      return res;
    } catch (_) {
      return false;
    }
  }

  /// Stops the service and cleans the previous registered callback
  static Future<void> stopCaller() async {
    await _channel.invokeMethod('stopCaller');
  }
}

void _callbackDispatcher() {
  print('me.leoletto - Callback dispatcher called from native code');

  // 1. Initialize MethodChannel used to communicate with the platform portion of the plugin.
  const MethodChannel _backgroundChannel =
      MethodChannel('me.leoletto.caller_background');

  // 2. Setup internal state needed for MethodChannels.
  WidgetsFlutterBinding.ensureInitialized();

  // 3. Listen for background events from the platform portion of the plugin.
  _backgroundChannel.setMethodCallHandler((MethodCall call) async {
    final args = call.arguments as List<dynamic>;
    print(
      'me.leoletto - Method call handler called from native code ${args.elementAt(3)}',
    );

    // 3.1. Retrieve callback instance for handle.
    final Function? userCallback = PluginUtilities.getCallbackFromHandle(
      CallbackHandle.fromRawHandle(args.elementAt(1)),
    );

    late CallerEvent callerEvent;
    switch (args.elementAt(3)) {
      case 'callEnded':
        callerEvent = CallerEvent.callEnded;
        break;
      case 'onMissedCall':
        callerEvent = CallerEvent.onMissedCall;
        break;
      case 'onIncomingCallAnswered':
        callerEvent = CallerEvent.onIncomingCallAnswered;
        break;
      case 'onIncomingCallReceived':
        callerEvent = CallerEvent.onIncomingCallReceived;
        break;
      default:
        throw Exception('Unkown event name');
    }

    // 3.3. Invoke callback.
    userCallback?.call(callerEvent, args.elementAt(2), args.elementAt(4));
  });

  // 4. Alert plugin that the callback handler is ready for events.
  // _backgroundChannel.invokeMethod('initialized');
}
