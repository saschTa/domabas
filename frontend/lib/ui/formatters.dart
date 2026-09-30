String formatLocalDateTime(DateTime value) =>
    value.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first;
