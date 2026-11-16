import 'dart:async';
import 'package:web/web.dart' as web;

StreamSubscription? setupWebBackGuard(void Function() onBackTriggered) {
  try {
    web.window.history.pushState(null, '', web.window.location.href);
    return web.EventStreamProviders.popStateEvent.forTarget(web.window).listen((event) {
      web.window.history.pushState(null, '', web.window.location.href);
      onBackTriggered();
    });
  } catch (_) {
    return null;
  }
}
