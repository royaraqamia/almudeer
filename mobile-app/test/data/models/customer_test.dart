import 'package:flutter_test/flutter_test.dart';
import 'package:almudeer_mobile_app/data/models/customer.dart';

void main() {
  group('Customer', () {
    test('should create from JSON with all fields', () {
      final json = {
        'id': 1,
        'phone': '+966501234567',
        'name': 'أحمد محمد',
        'company': 'Tech Corp',
        'last_contact_at': '2024-01-15T10:30:00Z',
        'created_at': '2024-01-01T08:00:00Z',
        'tags': 'vip, active',
        'notes': 'عميل مميز',
        'is_vip': true,
      };

      final customer = Customer.fromJson(json);

      expect(customer.id, 1);
      expect(customer.phone, '+966501234567');
      expect(customer.name, 'أحمد محمد');
      expect(customer.isVip, isTrue);
      expect(customer.tagsList, containsAll(['vip', 'active']));
    });

    test('should handle missing optional fields', () {
      final json = {
        'id': 2,
        'phone': '+966500000000',
        'is_vip': false,
        'created_at': '2024-01-01T00:00:00Z',
      };

      final customer = Customer.fromJson(json);

      expect(customer.id, 2);
      expect(customer.phone, '+966500000000');
      expect(customer.name, isNull);
    });

    test('should serialize to JSON correctly', () {
      final customer = Customer(
        id: 1,
        phone: '+966501234567',
        name: 'Test User',
        isVip: true,
        createdAt: '2024-01-01',
      );

      final json = customer.toJson();

      expect(json['id'], 1);
      expect(json['phone'], '+966501234567');
      expect(json['name'], 'Test User');
      expect(json['is_vip'], isTrue);
    });

    test('displayName returns name when available', () {
      final customer = Customer(
        id: 1,
        phone: '+966500000000',
        name: 'محمد علي',
        isVip: false,
        createdAt: '',
      );

      expect(customer.displayName, 'محمد علي');
    });

    test('displayName falls back to phone', () {
      final customer = Customer(
        id: 1,
        phone: '+966501234567',
        isVip: false,
        createdAt: '',
      );

      expect(customer.displayName, '+966501234567');
    });

    test('avatarInitials returns correct initials', () {
      final customer = Customer(
        id: 1,
        phone: '+966500000000',
        name: 'Ahmed Mohamed',
        isVip: false,
        createdAt: '',
      );

      expect(customer.avatarInitials, 'AM');
    });

    // sentimentDisplay tests removed
  });

  group('CustomersResponse', () {
    test('should parse from JSON correctly', () {
      final json = {
        'customers': [
          {
            'id': 1,
            'phone': '+966501234567',
            'name': 'Customer 1',
            'is_vip': false,
            'created_at': '',
          },
          {
            'id': 2,
            'phone': '+966509876543',
            'name': 'Customer 2',
            'is_vip': false,
            'created_at': '',
          },
        ],
        'total': 50,
        'has_more': true,
      };

      final response = CustomersResponse.fromJson(json);

      expect(response.customers.length, 2);
      expect(response.total, 50);
      expect(response.hasMore, isTrue);
    });
  });
}
