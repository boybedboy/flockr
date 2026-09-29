import 'package:flutter_test/flutter_test.dart';
import 'package:flockr/theme.dart';

void main() {
  test('care groups match the server keys', () {
    expect(CareGroup.all.map((g) => g.key), ['toddler', 'child', 'teen', 'adult', 'senior', 'special']);
    expect(CareGroup.of('guide').label, 'ไกด์');
  });
}
