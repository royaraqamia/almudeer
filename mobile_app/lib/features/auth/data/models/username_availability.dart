/// Username availability check response model
class UsernameAvailability {
  final bool available;
  final bool validFormat;
  final String message;
  final bool isUnknown;

  const UsernameAvailability({
    required this.available,
    required this.validFormat,
    required this.message,
    this.isUnknown = false,
  });

  factory UsernameAvailability.fromJson(Map<String, dynamic> json) {
    return UsernameAvailability(
      available: json['available'] ?? false,
      validFormat: json['valid_format'] ?? false,
      message: json['message'] ?? '',
      isUnknown: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'available': available,
      'valid_format': validFormat,
      'message': message,
    };
  }

  UsernameAvailability copyWith({
    bool? available,
    bool? validFormat,
    String? message,
    bool? isUnknown,
  }) {
    return UsernameAvailability(
      available: available ?? this.available,
      validFormat: validFormat ?? this.validFormat,
      message: message ?? this.message,
      isUnknown: isUnknown ?? this.isUnknown,
    );
  }
}
