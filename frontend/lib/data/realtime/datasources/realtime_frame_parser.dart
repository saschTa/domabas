import 'dart:convert';

const realtimeTopics = {
  'documents',
  'processing',
  'processing_configuration',
  'email',
  'paperless',
  'chat',
  'activity',
  'identity',
  'members',
  'system_users',
};

Map<String, Object> parseRealtimeFrame(Object? message) {
  if (message is! String || message.length > 512 || !_validUnicode(message)) {
    throw const FormatException('Invalid realtime frame');
  }
  if (utf8.encode(message).length > 512) {
    throw const FormatException('Realtime frame exceeds its limit');
  }
  return _RealtimeFrameParser(message).parse();
}

bool _validUnicode(String value) {
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= value.length) return false;
      final low = value.codeUnitAt(index);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

final class _RealtimeFrameParser {
  _RealtimeFrameParser(this.source);
  final String source;
  int position = 0;

  Never _invalid() => throw const FormatException('Invalid realtime frame');

  void _space() {
    while (position < source.length &&
        const {0x20, 0x09, 0x0a, 0x0d}.contains(source.codeUnitAt(position))) {
      position++;
    }
  }

  bool _take(String token) {
    _space();
    if (position >= source.length || source[position] != token) return false;
    position++;
    return true;
  }

  void _expect(String token) {
    if (!_take(token)) _invalid();
  }

  String _string() {
    _space();
    final start = position;
    _expect('"');
    var escaped = false;
    while (position < source.length) {
      final unit = source.codeUnitAt(position++);
      if (unit < 0x20) _invalid();
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x22) {
        final value = jsonDecode(source.substring(start, position));
        if (value is! String || !_validUnicode(value)) _invalid();
        return value;
      }
    }
    return _invalid();
  }

  List<String> _topics() {
    _expect('[');
    final result = <String>[];
    if (_take(']')) return result;
    while (true) {
      final topic = _string();
      if (result.length >= realtimeTopics.length ||
          !realtimeTopics.contains(topic) ||
          result.contains(topic)) {
        _invalid();
      }
      result.add(topic);
      if (_take(']')) return result;
      _expect(',');
    }
  }

  Map<String, Object> parse() {
    _expect('{');
    final result = <String, Object>{};
    if (_take('}')) _invalid();
    while (true) {
      final key = _string();
      if (result.containsKey(key)) _invalid();
      _expect(':');
      result[key] = switch (key) {
        'type' => _string(),
        'topics' => _topics(),
        'version' => _version(),
        _ => _invalid(),
      };
      if (_take('}')) break;
      _expect(',');
    }
    _space();
    if (position != source.length || result['version'] != 1) _invalid();
    final type = result['type'];
    if (!const {'ready', 'invalidate', 'resync', 'heartbeat'}.contains(type)) {
      _invalid();
    }
    if (type == 'heartbeat') {
      if (result.length != 2 || result.containsKey('topics')) _invalid();
    } else if (result.length != 3 || result['topics'] is! List<String>) {
      _invalid();
    }
    return result;
  }

  int _version() {
    _expect('1');
    return 1;
  }
}
