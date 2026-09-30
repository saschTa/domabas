import 'dart:async';

import 'package:domabas/domain/invoice/models/invoice.dart';
import 'package:domabas/presentation/invoice/cubits/invoices_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_invoice_repository.dart';

void main() {
  Future<InvoicesCubit> loadHistory(
    FakeInvoiceRepository repository, {
    int count = 60,
    int pages = 2,
  }) async {
    for (var index = 0; index < count; index++) {
      final invoice = invoiceFixture(index);
      repository.records[invoice.id] = invoice;
    }
    final cubit = InvoicesCubit(repository, allowed: true)..setActive(true);
    addTearDown(cubit.close);
    await pumpEventQueue();
    for (var page = 1; page < pages; page++) {
      await cubit.load(more: true);
    }
    return cubit;
  }

  test('refresh updates and removes older rows with bounded pages', () async {
    final repository = FakeInvoiceRepository();
    final cubit = await loadHistory(repository);
    final snapshotVersion = cubit.state.snapshotVersion;
    repository.records[invoiceFixture(25).id] = invoiceFixture(
      25,
      number: 'Corrected',
    );
    repository.records.remove(invoiceFixture(28).id);

    await cubit.load(background: true);

    expect(cubit.state.items, hasLength(40));
    expect(cubit.state.items[25].number, 'Corrected');
    expect(
      cubit.state.items.map((invoice) => invoice.id),
      isNot(contains(invoiceFixture(28).id)),
    );
    expect(cubit.state.items.last.id, invoiceFixture(40).id);
    expect(cubit.state.cursor, '40');
    expect(cubit.state.snapshotVersion, snapshotVersion);
    expect(cubit.state.browsingHistory, isTrue);
    expect(repository.cursors, [null, '20', null, '20']);
    expect(repository.limits, everyElement(20));
  });

  test(
    'head insertion keeps the loaded extent and complete continuation',
    () async {
      final repository = FakeInvoiceRepository();
      final cubit = await loadHistory(repository);
      final original = Map<String, Invoice>.of(repository.records);
      final head = invoiceFixture(99);
      repository.records
        ..clear()
        ..[head.id] = head
        ..addAll(original);

      await cubit.load(background: true);

      expect(cubit.state.items, hasLength(40));
      expect(cubit.state.items.first.id, head.id);
      expect(cubit.state.items.last.id, invoiceFixture(38).id);
      expect(cubit.state.cursor, '40');
      await cubit.load(more: true);
      await cubit.load(more: true);
      expect(cubit.state.items.map((invoice) => invoice.id), [
        head.id,
        ...original.keys,
      ]);
      expect(cubit.state.cursor, isNull);
      expect(repository.cursors, [null, '20', null, '20', '40', '60']);
    },
  );

  test('refresh follows and publishes new opaque continuations', () async {
    final repository = FakeInvoiceRepository();
    final cubit = await loadHistory(repository);
    final updated = [invoiceFixture(99), ...repository.records.values];
    repository.onList = (cursor, _) async => switch (cursor) {
      null => InvoicePage(
        items: updated.take(20),
        nextCursor: 'new-head-boundary',
      ),
      'new-head-boundary' => InvoicePage(
        items: updated.skip(20).take(20),
        nextCursor: 'new-history-boundary',
      ),
      'new-history-boundary' => InvoicePage(
        items: updated.skip(40).take(20),
        nextCursor: 'new-last-boundary',
      ),
      _ => throw const InvoiceFailure('invalid_response'),
    };

    await cubit.load(background: true);

    expect(cubit.state.cursor, 'new-history-boundary');
    expect(cubit.state.items, updated.take(40));
    await cubit.load(more: true);
    expect(cubit.state.items, updated.take(60));
    expect(cubit.state.cursor, 'new-last-boundary');
    expect(repository.cursors, [
      null,
      '20',
      null,
      'new-head-boundary',
      'new-history-boundary',
    ]);
  });

  test(
    'partial windows stay bounded and a shortened history reaches its end',
    () async {
      final repository = FakeInvoiceRepository();
      final cubit = await loadHistory(repository, count: 25);
      final head = invoiceFixture(99);
      final original = Map<String, Invoice>.of(repository.records);
      repository.records
        ..clear()
        ..[head.id] = head
        ..addAll(original);

      await cubit.load(background: true);

      expect(cubit.state.items, hasLength(25));
      expect(cubit.state.cursor, '25');
      expect(repository.limits, [20, 20, 20, 5]);
      await cubit.load(more: true);
      expect(cubit.state.items, hasLength(26));
      expect(cubit.state.cursor, isNull);

      repository.records.removeWhere((id, _) => id != head.id);
      await cubit.load(background: true);
      expect(cubit.state.items.single.id, head.id);
      expect(cubit.state.cursor, isNull);
      expect(repository.cursors, [null, '20', null, '20', '25', null]);
      repository.records.clear();
      await cubit.load(background: true);
      expect(cubit.state.items, isEmpty);
      repository.records[head.id] = head;
      await cubit.load(background: true);
      expect(cubit.state.items.single.id, head.id);
    },
  );

  test(
    'later-page failure preserves the complete prior snapshot and cursor',
    () async {
      final repository = FakeInvoiceRepository();
      final cubit = await loadHistory(repository);
      final previous = cubit.state;
      repository.onList = (cursor, _) async {
        if (cursor != null) throw const InvoiceFailure('unavailable');
        return InvoicePage(
          items: [invoiceFixture(99)],
          nextCursor: 'changed-head',
        );
      };

      await cubit.load(background: true);

      expect(cubit.state.items, previous.items);
      expect(cubit.state.cursor, previous.cursor);
      expect(cubit.state.snapshotVersion, previous.snapshotVersion);
      expect(cubit.state.error, isNotNull);
      expect(repository.cursors, [null, '20', null, 'changed-head']);
      repository.onList = null;
      await cubit.load(background: true);
      expect(cubit.state.items, previous.items);
      expect(cubit.state.error, isNull);
    },
  );

  test(
    'filter changes cancel later refresh pages and fence remaining work',
    () async {
      final repository = FakeInvoiceRepository();
      final cubit = await loadHistory(repository, count: 80, pages: 3);
      final previous = cubit.state;
      final pending = Completer<InvoicePage>();
      final selected = invoiceFixture(99, source: 'ai');
      repository.onList = (cursor, source) async {
        if (source == 'ai') return InvoicePage(items: [selected]);
        if (cursor != null) return pending.future;
        return InvoicePage(items: previous.items.take(20), nextCursor: '20');
      };
      final refresh = cubit.load(background: true);
      await pumpEventQueue();
      var cancelled = false;
      unawaited(repository.cancellations.last!.then((_) => cancelled = true));

      cubit.filter('ai');
      await pumpEventQueue();
      pending.complete(
        InvoicePage(items: previous.items.skip(20).take(20), nextCursor: '40'),
      );
      await refresh;

      expect(cancelled, isTrue);
      expect(cubit.state.items.single.id, selected.id);
      expect(cubit.state.snapshot!.source, 'ai');
      expect(cubit.state.snapshotVersion, previous.snapshotVersion + 1);
      expect(cubit.state.cursor, isNull);
      expect(repository.cursors, [null, '20', '40', null, '20', null]);
    },
  );

  test(
    'foreground continuation supersedes the pending background window',
    () async {
      final repository = FakeInvoiceRepository();
      final cubit = await loadHistory(repository);
      final previous = cubit.state;
      final pending = Completer<InvoicePage>();
      repository.onList = (cursor, _) async {
        if (cursor == '20') return pending.future;
        if (cursor == '40') {
          return InvoicePage(items: repository.records.values.skip(40));
        }
        return InvoicePage(items: previous.items.take(20), nextCursor: '20');
      };
      final refresh = cubit.load(background: true);
      await pumpEventQueue();
      var cancelled = false;
      unawaited(repository.cancellations.last!.then((_) => cancelled = true));
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.canPaginate, isTrue);

      await cubit.load(more: true);
      pending.complete(InvoicePage(items: [invoiceFixture(99)]));
      await refresh;

      expect(cancelled, isTrue);
      expect(cubit.state.items, repository.records.values);
      expect(cubit.state.cursor, isNull);
      expect(cubit.state.snapshotVersion, previous.snapshotVersion);
      expect(repository.cursors, [null, '20', null, '20', '40']);
    },
  );
}
