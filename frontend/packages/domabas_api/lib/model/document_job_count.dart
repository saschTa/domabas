// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentJobCount {
  DocumentJobCount({
    required this.pipeline,
    required this.status,
    required this.count,
  });

  DocumentJobCountPipelineEnum pipeline;

  String status;

  int count;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentJobCount &&
    other.pipeline == pipeline &&
    other.status == status &&
    other.count == count;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (pipeline.hashCode) +
    (status.hashCode) +
    (count.hashCode);

  @override
  String toString() => 'DocumentJobCount[pipeline=$pipeline, status=$status, count=$count]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'pipeline'] = this.pipeline;
      json[r'status'] = this.status;
      json[r'count'] = this.count;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentJobCount? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'pipeline'), 'Required key "DocumentJobCount[pipeline]" is missing from JSON.');
        assert(json[r'pipeline'] != null, 'Required key "DocumentJobCount[pipeline]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "DocumentJobCount[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "DocumentJobCount[status]" has a null value in JSON.');
        assert(json.containsKey(r'count'), 'Required key "DocumentJobCount[count]" is missing from JSON.');
        assert(json[r'count'] != null, 'Required key "DocumentJobCount[count]" has a null value in JSON.');
        return true;
      }());

      return DocumentJobCount(
        pipeline: DocumentJobCountPipelineEnum.fromJson(json[r'pipeline'])!,
        status: mapValueOfType<String>(json, r'status')!,
        count: mapValueOfType<int>(json, r'count')!,
      );
    }
    return null;
  }

  static List<DocumentJobCount> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJobCount>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJobCount.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentJobCount> mapFromJson(dynamic json) {
    final map = <String, DocumentJobCount>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentJobCount.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentJobCount>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentJobCount>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentJobCount.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'pipeline',
    'status',
    'count',
  };
}

enum DocumentJobCountPipelineEnum {
  ingestion._(r'ingestion'),
  ai._(r'ai'),
  thumbnail._(r'thumbnail'),
  ;

  const DocumentJobCountPipelineEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentJobCountPipelineEnum? fromJson(dynamic value) => DocumentJobCountPipelineEnumTypeTransformer().decode(value);

  static List<DocumentJobCountPipelineEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentJobCountPipelineEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentJobCountPipelineEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentJobCountPipelineEnumTypeTransformer {
  factory DocumentJobCountPipelineEnumTypeTransformer() => _instance ??= const DocumentJobCountPipelineEnumTypeTransformer._();

  const DocumentJobCountPipelineEnumTypeTransformer._();

  String encode(DocumentJobCountPipelineEnum data) => data._value;

  DocumentJobCountPipelineEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentJobCountPipelineEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ingestion': return DocumentJobCountPipelineEnum.ingestion;
        case r'ai': return DocumentJobCountPipelineEnum.ai;
        case r'thumbnail': return DocumentJobCountPipelineEnum.thumbnail;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentJobCountPipelineEnumTypeTransformer? _instance;
}
