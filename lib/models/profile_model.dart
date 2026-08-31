class Profile {
  String id;
  String name;
  String phone;
  String email;
  String createdAt;
  String updatedAt;

  Profile(
    this.id,
    this.name,
    this.phone,
    this.email, {
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      json['id'] as String,
      json['name'] as String? ?? '',
      json['phone'] as String? ?? '',
      json['email'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
    };
  }
}
