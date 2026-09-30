import 'dart:convert';

import 'document.dart';

abstract final class DocumentUploadValidation {
  static Map<String, String> validate(DocumentProperties value) {
    final errors = <String, String>{};
    void field(
      String name,
      String text,
      int runes,
      int bytes, {
      bool description = false,
    }) {
      if (!validScalars(text) ||
          text.runes.any(
            (r) => r == 0 || !description && (r < 32 || r >= 127 && r <= 159),
          )) {
        errors[name] = 'Remove unsupported control characters.';
      } else if (text.runes.length > runes ||
          utf8.encode(text).length > bytes) {
        errors[name] = 'Use $runes characters or fewer.';
      }
    }

    field('title', value.title, 200, 800);
    if (trim(value.title).isEmpty) errors['title'] = 'Enter a document title.';
    field('description', value.description, 4000, 16000, description: true);
    field('sender', trim(value.sender), 320, 1280);
    field('subject', trim(value.subject), 200, 800);
    field('messageId', trim(value.messageId), 512, 2048);
    if (!const {'document', 'letter', 'email'}.contains(value.kind)) {
      errors['kind'] = 'Choose a document kind.';
    }
    for (final entry in {
      'tags': value.tags,
      'recipients': value.recipients,
      'cc': value.cc,
      'bcc': value.bcc,
    }.entries) {
      final tags = entry.key == 'tags';
      if (entry.value.length > 20) errors[entry.key] = 'Use 20 items or fewer.';
      final seen = <String>{};
      for (final raw in entry.value) {
        final item = tags ? lowercase(trim(raw)) : trim(raw);
        field(entry.key, item, tags ? 64 : 320, tags ? 256 : 1280);
        if (item.isEmpty) errors[entry.key] = 'Remove empty items.';
        if (!seen.add(item)) errors[entry.key] = 'Remove duplicate items.';
      }
    }
    final date = value.documentDate;
    if (date.isNotEmpty) {
      final parsed = DateTime.tryParse(date);
      if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.year < 1 ||
          parsed.year > 9999 ||
          parsed.toIso8601String().substring(0, 10) != date) {
        errors['documentDate'] = 'Enter a valid date as YYYY-MM-DD.';
      }
    }
    for (final entry in {
      'title': [value.title],
      'description': [value.description],
      'sender': [value.sender],
      'subject': [value.subject],
      'messageId': [value.messageId],
      'documentDate': [value.documentDate],
      'kind': [value.kind],
      'tags': value.tags,
      'recipients': value.recipients,
      'cc': value.cc,
      'bcc': value.bcc,
    }.entries) {
      if (entry.value.any(
        (raw) => !validScalars(raw) || raw.contains('\u0000'),
      )) {
        errors[entry.key] = 'Remove invalid text characters.';
      }
    }
    return Map.unmodifiable(errors);
  }

  static DocumentProperties normalize(DocumentProperties value) {
    final errors = validate(value);
    if (errors.isNotEmpty) throw ArgumentError(errors.values.first);
    final tags = value.tags.map((tag) => lowercase(trim(tag))).toList()
      ..sort(_scalarCompare);
    return DocumentProperties(
      title: trim(value.title),
      description: value.description,
      tags: tags,
      kind: value.kind,
      sender: trim(value.sender),
      recipients: value.recipients.map(trim),
      cc: value.cc.map(trim),
      bcc: value.bcc.map(trim),
      documentDate: value.documentDate,
      subject: trim(value.subject),
      messageId: trim(value.messageId),
    );
  }

  static String lowercase(String value) => String.fromCharCodes(
    value.runes.map(
      (rune) => rune == 0x130
          ? 0x69
          : String.fromCharCode(rune).toLowerCase().runes.first,
    ),
  );
  static int _scalarCompare(String a, String b) {
    final x = a.runes.toList(), y = b.runes.toList();
    for (var i = 0; i < x.length && i < y.length; i++) {
      if (x[i] != y[i]) return x[i].compareTo(y[i]);
    }
    return x.length.compareTo(y.length);
  }

  static String trim(String value) {
    if (!validScalars(value)) return value;
    final points = value.runes.toList();
    var first = 0, last = points.length;
    while (first < last && _space(points[first])) {
      first++;
    }
    while (last > first && _space(points[last - 1])) {
      last--;
    }
    return String.fromCharCodes(points.sublist(first, last));
  }

  static bool _space(int r) =>
      r >= 9 && r <= 13 ||
      const {
        32,
        0x85,
        0xa0,
        0x1680,
        0x2028,
        0x2029,
        0x202f,
        0x205f,
        0x3000,
      }.contains(r) ||
      r >= 0x2000 && r <= 0x200a;
  static bool validScalars(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= value.length ||
            value.codeUnitAt(i) < 0xdc00 ||
            value.codeUnitAt(i) > 0xdfff) {
          return false;
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return false;
      }
    }
    return true;
  }
}
