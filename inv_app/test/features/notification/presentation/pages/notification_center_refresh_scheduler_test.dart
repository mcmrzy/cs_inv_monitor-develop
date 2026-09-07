import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/notification/presentation/pages/notification_center_page.dart';

void main() {
  group('NotificationRefreshScheduler', () {
    test('debounces a burst until the last event window completes', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final scheduler = NotificationRefreshScheduler(
          onRefresh: () => refreshCount++,
        );

        scheduler.schedule();
        async.elapse(const Duration(milliseconds: 100));
        scheduler.schedule();
        async.elapse(const Duration(milliseconds: 100));
        scheduler.schedule();

        async.elapse(const Duration(milliseconds: 299));
        expect(refreshCount, 0);

        async.elapse(const Duration(milliseconds: 1));
        expect(refreshCount, 1);
      });
    });

    test('allows a new scheduled refresh after the window completes', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final scheduler = NotificationRefreshScheduler(
          onRefresh: () => refreshCount++,
        );

        scheduler.schedule();
        async.elapse(const Duration(milliseconds: 300));
        scheduler.schedule();
        async.elapse(const Duration(milliseconds: 300));

        expect(refreshCount, 2);
      });
    });

    test('refreshNow is immediate and replaces a pending scheduled refresh', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final scheduler = NotificationRefreshScheduler(
          onRefresh: () => refreshCount++,
        );

        scheduler.schedule();
        scheduler.refreshNow();

        expect(refreshCount, 1);
        async.elapse(const Duration(milliseconds: 300));
        expect(refreshCount, 1);
      });
    });

    test('dispose cancels a pending refresh and ignores later schedules', () {
      fakeAsync((async) {
        var refreshCount = 0;
        final scheduler = NotificationRefreshScheduler(
          onRefresh: () => refreshCount++,
        );

        scheduler.schedule();
        scheduler.dispose();
        scheduler.schedule();
        async.elapse(const Duration(milliseconds: 300));

        expect(refreshCount, 0);
      });
    });
  });
}
