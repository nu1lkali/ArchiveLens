import 'package:flutter/services.dart';

/// 接收 native 层（windows/runner/flutter_window.cpp）发来的拖放事件。
///
/// 走 MethodChannel 而不是 `desktop_drop` 之类的插件，是为了不再引入插件依赖
/// （也就不用再处理插件编译和符号链接）。
class DropService {
  static const MethodChannel _channel = MethodChannel('archive_lens/drop');

  final void Function(String path) onDirectoryDropped;

  DropService(this.onDirectoryDropped) {
    _channel.setMethodCallHandler(_handle);
  }

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'drop') {
      final path = call.arguments;
      if (path is String && path.isNotEmpty) {
        onDirectoryDropped(path);
      }
    }
    return null;
  }
}
