export 'document_upload_acquisition_stub.dart'
    if (dart.library.io) 'document_upload_acquisition_native.dart'
    if (dart.library.js_interop) 'document_upload_acquisition_web.dart';
