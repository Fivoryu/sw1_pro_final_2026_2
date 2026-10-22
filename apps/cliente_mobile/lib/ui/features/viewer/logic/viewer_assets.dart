import 'package:flutter/foundation.dart';

/// The walkthrough page is served from a virtual origin instead of `file://`.
///
/// Chromium refuses to fetch ES module scripts from a `file://` page:
/// `Access to script at 'file:///…/viewer.js' from origin 'null' has been
/// blocked by CORS policy`. The viewer is a module graph (`viewer.js` imports
/// `geometry.mjs` and Three.js), so the WebView intercepts this origin and
/// serves the bundled assets itself — still local, still controlled, but with
/// an origin the module loader accepts.
const viewerOrigin = 'https://appassets.local';

const String _assetPrefix = 'assets/viewer/';

/// The only files the page may fetch, with the MIME type the module loader
/// needs. Anything else is refused, so the WebView never serves arbitrary
/// bundle content to the walkthrough.
const Map<String, String> _servedAssets = {
  '${_assetPrefix}index.html': 'text/html',
  '${_assetPrefix}viewer.js': 'text/javascript',
  '${_assetPrefix}geometry.mjs': 'text/javascript',
  '${_assetPrefix}three.module.min.js': 'text/javascript',
};

/// Asset key for [uri], or null when this request must not be served.
///
/// Percent-encoded and `..` segments are rejected: only a single whitelisted
/// file name under the viewer origin resolves.
String? viewerAssetKeyFor(Uri uri) {
  if (uri.scheme != 'https' || uri.host != 'appassets.local') return null;
  final segments = uri.pathSegments;
  if (segments.length != 1) return null;
  final key = '$_assetPrefix${segments.single}';
  return _servedAssets.containsKey(key) ? key : null;
}

/// MIME type for a served [assetKey], or null when it is not served at all.
String? contentTypeForViewerAsset(String assetKey) => _servedAssets[assetKey];

/// The bridge shim injected before the page runs: it keeps the viewer's
/// `window.RoomForgeBridge.postMessage` contract while routing messages to the
/// plugin's JavaScript handler. No token or secret ever enters this channel.
const String viewerBridgeShim = '''
window.RoomForgeBridge = window.RoomForgeBridge || {
  postMessage: function (message) {
    window.flutter_inappwebview.callHandler('RoomForgeBridge', String(message));
  }
};
''';

@visibleForTesting
const List<String> servedViewerAssets = [
  'assets/viewer/index.html',
  'assets/viewer/viewer.js',
  'assets/viewer/geometry.mjs',
  'assets/viewer/three.module.min.js',
];
