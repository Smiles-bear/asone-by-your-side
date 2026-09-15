import 'dart:async';

class ModelServiceChangeEvents {
  ModelServiceChangeEvents._();

  static final StreamController<String> _controller =
      StreamController<String>.broadcast(sync: true);

  static Stream<String> get changes => _controller.stream;

  static void notify(String modelServiceId) {
    if (!_controller.isClosed) _controller.add(modelServiceId);
  }
}
