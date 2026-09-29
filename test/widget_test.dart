import 'package:flutter_test/flutter_test.dart';
import 'package:taskhub/main.dart';

void main() {
  test('deadline keeps its completion state and date', () {
    final deadline = DeadlineItem(
      id: '42', title: 'Essay', subject: 'English',
      due: DateTime(2026, 10, 1, 12), completed: false,
      colorValue: 0xff123456, iconCodePoint: 1,
    );
    final completed = deadline.copyWith(completed: true);
    expect(completed.completed, isTrue);
    expect(completed.due, deadline.due);
    expect(DeadlineItem.fromJson(completed.toJson()).completed, isTrue);
  });
}
