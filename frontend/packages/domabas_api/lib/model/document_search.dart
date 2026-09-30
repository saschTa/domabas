// AUTO-GENERATED FILE, DO NOT MODIFY!
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DocumentSearch {
  DocumentSearch({
    required this.query,
    required this.mode,
    this.kinds = const [],
    this.tags = const [],
    this.sender,
    this.senderMatch,
    this.recipient,
    this.recipientMatch,
    this.sort,
    this.cursor,
    this.limit = 20,
    this.offset = 0,
  });

  String query;

  DocumentSearchModeEnum mode;

  List<DocumentSearchKindsEnum> kinds;

  List<String> tags;

  String? sender;

  DocumentSearchSenderMatchEnum? senderMatch;

  String? recipient;

  DocumentSearchRecipientMatchEnum? recipientMatch;

  DocumentSearchSortEnum? sort;

  String? cursor;

  int limit;

  int offset;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DocumentSearch &&
    other.query == query &&
    other.mode == mode &&
    _deepEquality.equals(other.kinds, kinds) &&
    _deepEquality.equals(other.tags, tags) &&
    other.sender == sender &&
    other.senderMatch == senderMatch &&
    other.recipient == recipient &&
    other.recipientMatch == recipientMatch &&
    other.sort == sort &&
    other.cursor == cursor &&
    other.limit == limit &&
    other.offset == offset;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (query.hashCode) +
    (mode.hashCode) +
    (kinds.hashCode) +
    (tags.hashCode) +
    (sender == null ? 0 : sender!.hashCode) +
    (senderMatch == null ? 0 : senderMatch!.hashCode) +
    (recipient == null ? 0 : recipient!.hashCode) +
    (recipientMatch == null ? 0 : recipientMatch!.hashCode) +
    (sort == null ? 0 : sort!.hashCode) +
    (cursor == null ? 0 : cursor!.hashCode) +
    (limit.hashCode) +
    (offset.hashCode);

  @override
  String toString() => 'DocumentSearch[query=$query, mode=$mode, kinds=$kinds, tags=$tags, sender=$sender, senderMatch=$senderMatch, recipient=$recipient, recipientMatch=$recipientMatch, sort=$sort, cursor=$cursor, limit=$limit, offset=$offset]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'query'] = this.query;
      json[r'mode'] = this.mode;
      json[r'kinds'] = this.kinds;
      json[r'tags'] = this.tags;
    if (this.sender != null) {
      json[r'sender'] = this.sender;
    } else {
      json[r'sender'] = null;
    }
    if (this.senderMatch != null) {
      json[r'senderMatch'] = this.senderMatch;
    } else {
      json[r'senderMatch'] = null;
    }
    if (this.recipient != null) {
      json[r'recipient'] = this.recipient;
    } else {
      json[r'recipient'] = null;
    }
    if (this.recipientMatch != null) {
      json[r'recipientMatch'] = this.recipientMatch;
    } else {
      json[r'recipientMatch'] = null;
    }
    if (this.sort != null) {
      json[r'sort'] = this.sort;
    } else {
      json[r'sort'] = null;
    }
    if (this.cursor != null) {
      json[r'cursor'] = this.cursor;
    } else {
      json[r'cursor'] = null;
    }
      json[r'limit'] = this.limit;
      json[r'offset'] = this.offset;
    return json;
  }

  // ignore: prefer_constructors_over_static_methods
  static DocumentSearch? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      assert(() {
        assert(json.containsKey(r'query'), 'Required key "DocumentSearch[query]" is missing from JSON.');
        assert(json[r'query'] != null, 'Required key "DocumentSearch[query]" has a null value in JSON.');
        assert(json.containsKey(r'mode'), 'Required key "DocumentSearch[mode]" is missing from JSON.');
        assert(json[r'mode'] != null, 'Required key "DocumentSearch[mode]" has a null value in JSON.');
        return true;
      }());

      return DocumentSearch(
        query: mapValueOfType<String>(json, r'query')!,
        mode: DocumentSearchModeEnum.fromJson(json[r'mode'])!,
        kinds: DocumentSearchKindsEnum.listFromJson(json[r'kinds']),
        tags: json[r'tags'] is Iterable
            ? (json[r'tags'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        sender: mapValueOfType<String>(json, r'sender'),
        senderMatch: DocumentSearchSenderMatchEnum.fromJson(json[r'senderMatch']),
        recipient: mapValueOfType<String>(json, r'recipient'),
        recipientMatch: DocumentSearchRecipientMatchEnum.fromJson(json[r'recipientMatch']),
        sort: DocumentSearchSortEnum.fromJson(json[r'sort']),
        cursor: mapValueOfType<String>(json, r'cursor'),
        limit: mapValueOfType<int>(json, r'limit') ?? 20,
        offset: mapValueOfType<int>(json, r'offset') ?? 0,
      );
    }
    return null;
  }

  static List<DocumentSearch> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearch>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearch.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DocumentSearch> mapFromJson(dynamic json) {
    final map = <String, DocumentSearch>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DocumentSearch.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  static Map<String, List<DocumentSearch>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DocumentSearch>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DocumentSearch.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  static const requiredKeys = <String>{
    'query',
    'mode',
  };
}

enum DocumentSearchModeEnum {
  fulltext._(r'fulltext'),
  semantic._(r'semantic'),
  hybrid._(r'hybrid'),
  ;

  const DocumentSearchModeEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentSearchModeEnum? fromJson(dynamic value) => DocumentSearchModeEnumTypeTransformer().decode(value);

  static List<DocumentSearchModeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchModeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchModeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentSearchModeEnumTypeTransformer {
  factory DocumentSearchModeEnumTypeTransformer() => _instance ??= const DocumentSearchModeEnumTypeTransformer._();

  const DocumentSearchModeEnumTypeTransformer._();

  String encode(DocumentSearchModeEnum data) => data._value;

  DocumentSearchModeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentSearchModeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'fulltext': return DocumentSearchModeEnum.fulltext;
        case r'semantic': return DocumentSearchModeEnum.semantic;
        case r'hybrid': return DocumentSearchModeEnum.hybrid;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentSearchModeEnumTypeTransformer? _instance;
}

enum DocumentSearchKindsEnum {
  document._(r'document'),
  letter._(r'letter'),
  email._(r'email'),
  ;

  const DocumentSearchKindsEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentSearchKindsEnum? fromJson(dynamic value) => DocumentSearchKindsEnumTypeTransformer().decode(value);

  static List<DocumentSearchKindsEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchKindsEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchKindsEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentSearchKindsEnumTypeTransformer {
  factory DocumentSearchKindsEnumTypeTransformer() => _instance ??= const DocumentSearchKindsEnumTypeTransformer._();

  const DocumentSearchKindsEnumTypeTransformer._();

  String encode(DocumentSearchKindsEnum data) => data._value;

  DocumentSearchKindsEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentSearchKindsEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'document': return DocumentSearchKindsEnum.document;
        case r'letter': return DocumentSearchKindsEnum.letter;
        case r'email': return DocumentSearchKindsEnum.email;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentSearchKindsEnumTypeTransformer? _instance;
}

enum DocumentSearchSenderMatchEnum {
  contains._(r'contains'),
  exact._(r'exact'),
  ;

  const DocumentSearchSenderMatchEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentSearchSenderMatchEnum? fromJson(dynamic value) => DocumentSearchSenderMatchEnumTypeTransformer().decode(value);

  static List<DocumentSearchSenderMatchEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchSenderMatchEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchSenderMatchEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentSearchSenderMatchEnumTypeTransformer {
  factory DocumentSearchSenderMatchEnumTypeTransformer() => _instance ??= const DocumentSearchSenderMatchEnumTypeTransformer._();

  const DocumentSearchSenderMatchEnumTypeTransformer._();

  String encode(DocumentSearchSenderMatchEnum data) => data._value;

  DocumentSearchSenderMatchEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentSearchSenderMatchEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'contains': return DocumentSearchSenderMatchEnum.contains;
        case r'exact': return DocumentSearchSenderMatchEnum.exact;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentSearchSenderMatchEnumTypeTransformer? _instance;
}

enum DocumentSearchRecipientMatchEnum {
  contains._(r'contains'),
  exact._(r'exact'),
  ;

  const DocumentSearchRecipientMatchEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentSearchRecipientMatchEnum? fromJson(dynamic value) => DocumentSearchRecipientMatchEnumTypeTransformer().decode(value);

  static List<DocumentSearchRecipientMatchEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchRecipientMatchEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchRecipientMatchEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentSearchRecipientMatchEnumTypeTransformer {
  factory DocumentSearchRecipientMatchEnumTypeTransformer() => _instance ??= const DocumentSearchRecipientMatchEnumTypeTransformer._();

  const DocumentSearchRecipientMatchEnumTypeTransformer._();

  String encode(DocumentSearchRecipientMatchEnum data) => data._value;

  DocumentSearchRecipientMatchEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentSearchRecipientMatchEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'contains': return DocumentSearchRecipientMatchEnum.contains;
        case r'exact': return DocumentSearchRecipientMatchEnum.exact;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentSearchRecipientMatchEnumTypeTransformer? _instance;
}

enum DocumentSearchSortEnum {
  relevance._(r'relevance'),
  newest._(r'newest'),
  oldest._(r'oldest'),
  title._(r'title'),
  dateNewest._(r'date-newest'),
  dateOldest._(r'date-oldest'),
  ;

  const DocumentSearchSortEnum._(this._value);

  final String _value;

  @override
  String toString() => _value;

  String toJson() => _value;

  static DocumentSearchSortEnum? fromJson(dynamic value) => DocumentSearchSortEnumTypeTransformer().decode(value);

  static List<DocumentSearchSortEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DocumentSearchSortEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DocumentSearchSortEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

class DocumentSearchSortEnumTypeTransformer {
  factory DocumentSearchSortEnumTypeTransformer() => _instance ??= const DocumentSearchSortEnumTypeTransformer._();

  const DocumentSearchSortEnumTypeTransformer._();

  String encode(DocumentSearchSortEnum data) => data._value;

  DocumentSearchSortEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DocumentSearchSortEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'relevance': return DocumentSearchSortEnum.relevance;
        case r'newest': return DocumentSearchSortEnum.newest;
        case r'oldest': return DocumentSearchSortEnum.oldest;
        case r'title': return DocumentSearchSortEnum.title;
        case r'date-newest': return DocumentSearchSortEnum.dateNewest;
        case r'date-oldest': return DocumentSearchSortEnum.dateOldest;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  static DocumentSearchSortEnumTypeTransformer? _instance;
}
