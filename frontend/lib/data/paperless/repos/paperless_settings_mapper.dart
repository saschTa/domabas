import 'package:domabas_api/api.dart' as api;

import '../../../domain/paperless/models/paperless_settings.dart';

PaperlessSettings paperlessSettingsMapper(api.PaperlessSettings value) {
  final minimum = value.minimumRetrievalConcurrency.toJson();
  final maximum = value.maximumRetrievalConcurrency.toJson();
  if (value.revision < 1 ||
      minimum < 1 ||
      maximum > 10 ||
      minimum > maximum ||
      value.retrievalConcurrency < minimum ||
      value.retrievalConcurrency > maximum) {
    throw const FormatException('Invalid Paperless settings');
  }
  return PaperlessSettings(
    retrievalConcurrency: value.retrievalConcurrency,
    revision: value.revision,
    minimumRetrievalConcurrency: minimum,
    maximumRetrievalConcurrency: maximum,
  );
}
