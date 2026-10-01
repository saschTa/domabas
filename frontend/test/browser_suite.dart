@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import 'document_rendering_browser_independent_test.dart' as document_rendering;
import 'document_upload_acquisition_browser_test.dart' as upload_acquisition;
import 'document_upload_transport_test.dart' as upload_transport;
import 'document_vocabulary_transport_independent_test.dart' as vocabulary;
import 'identity_clipboard_browser_test.dart' as clipboard;
import 'realtime_browser_independent_test.dart' as realtime_browser;
import 'realtime_frame_independent_test.dart' as realtime_frames;
import 'realtime_transport_independent_test.dart' as realtime_transport;
import 'scanner_images_browser_independent_test.dart' as scanner_images;
import 'unit/scanner_validation_independent_test.dart' as scanner_validation;

void main() {
  group('HTTP invitation clipboard', clipboard.main);
  group('Realtime frames', realtime_frames.main);
  group('Realtime transport', realtime_transport.main);
  group('Realtime browser lifetime', realtime_browser.main);
  group('Scanner validation', scanner_validation.main);
  group('Scanner rendering', scanner_images.main);
  group('Document vocabulary', vocabulary.main);
  group('Document rendering', document_rendering.main);
  group('Upload transport', upload_transport.main);
  group('Upload acquisition', upload_acquisition.main);
}
