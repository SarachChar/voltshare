import 'package:flutter_test/flutter_test.dart';
import 'package:voltshare_app/models/station_model.dart';

void main() {
  test('StationImage.fromJson and copyWith', () {
    final image = StationImage.fromJson({
      'id': 'i1',
      'station_id': 's1',
      'image_url': 'station/s1/1.jpg',
      'display_order': 2,
    });
    expect(image.id, 'i1');
    expect(image.stationId, 's1');
    expect(image.imageUrl, 'station/s1/1.jpg');
    expect(image.displayOrder, 2);

    final resolved = image.copyWith(imageUrl: 'https://x/1.jpg');
    expect(resolved.imageUrl, 'https://x/1.jpg');
    expect(resolved.id, 'i1');
    expect(resolved.displayOrder, 2);
  });

  test('StationBusinessImage.fromJson defaults display_order to 0', () {
    final image = StationBusinessImage.fromJson({
      'id': 'b1',
      'station_id': 's1',
      'image_url': 'u',
      'display_order': null,
    });
    expect(image.displayOrder, 0);
    expect(image.stationId, 's1');
  });

  test('StationBusiness.fromJson', () {
    final business = StationBusiness.fromJson({
      'id': 'x',
      'station_id': 's1',
      'business_type': 'CAFE',
      'business_name': 'Bean & Bolt',
      'description': null,
    });
    expect(business.businessType, 'CAFE');
    expect(business.businessName, 'Bean & Bolt');
    expect(business.description, '');
  });

  group('StationPromotion', () {
    test('fromJson parses dates to local time and defaults status', () {
      final promo = StationPromotion.fromJson({
        'id': 'p1',
        'station_id': 's1',
        'title': '10% off',
        'valid_from': '2026-01-01T00:00:00Z',
        'valid_until': null,
      });
      expect(promo.title, '10% off');
      expect(promo.status, 'ACTIVE');
      expect(promo.isActive, isTrue);
      expect(promo.validFrom, DateTime.utc(2026, 1, 1).toLocal());
      expect(promo.validUntil, isNull);
    });

    test('isActive is case-insensitive', () {
      const promo = StationPromotion(
        id: 'p',
        stationId: 's',
        title: 't',
        status: 'INACTIVE',
      );
      expect(promo.isActive, isFalse);
    });

    test('validRangeLabel covers every combination', () {
      final from = DateTime(2026, 1, 1);
      final until = DateTime(2026, 3, 31);
      StationPromotion make({DateTime? f, DateTime? u}) => StationPromotion(
            id: 'p',
            stationId: 's',
            title: 't',
            validFrom: f,
            validUntil: u,
          );

      expect(make().validRangeLabel, 'No expiry');
      expect(make(f: from, u: until).validRangeLabel,
          '1 Jan 2026 - 31 Mar 2026');
      expect(make(u: until).validRangeLabel, 'Until 31 Mar 2026');
      expect(make(f: from).validRangeLabel, 'From 1 Jan 2026');
    });
  });
}
