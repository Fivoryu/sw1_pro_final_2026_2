import 'package:cliente_mobile/ui/features/viewer/logic/viewer_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('viewer asset resolution', () {
    test('serves the four bundled viewer files from the virtual origin', () {
      expect(
        viewerAssetKeyFor(Uri.parse('https://appassets.local/index.html')),
        'assets/viewer/index.html',
      );
      expect(
        viewerAssetKeyFor(Uri.parse('https://appassets.local/viewer.js')),
        'assets/viewer/viewer.js',
      );
      expect(
        viewerAssetKeyFor(Uri.parse('https://appassets.local/geometry.mjs')),
        'assets/viewer/geometry.mjs',
      );
      expect(
        viewerAssetKeyFor(Uri.parse('https://appassets.local/three.module.min.js')),
        'assets/viewer/three.module.min.js',
      );
    });

    test('refuses anything outside the whitelist, traversal included', () {
      expect(
        viewerAssetKeyFor(Uri.parse('https://appassets.local/../pubspec.yaml')),
        isNull,
      );
      expect(
        viewerAssetKeyFor(Uri.parse('https://appassets.local/%2e%2e/pubspec.yaml')),
        isNull,
      );
      expect(
        viewerAssetKeyFor(Uri.parse('https://appassets.local/pubspec.yaml')),
        isNull,
      );
      expect(
        viewerAssetKeyFor(Uri.parse('https://evil.example/index.html')),
        isNull,
        reason: 'the walkthrough never loads content from another origin',
      );
    });

    test('maps the MIME types a module graph needs', () {
      expect(contentTypeForViewerAsset('assets/viewer/index.html'), 'text/html');
      expect(contentTypeForViewerAsset('assets/viewer/viewer.js'), 'text/javascript');
      expect(contentTypeForViewerAsset('assets/viewer/geometry.mjs'), 'text/javascript');
      expect(contentTypeForViewerAsset('assets/viewer/unknown.txt'), isNull);
    });
  });
}
