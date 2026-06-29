class User {
  final int id;
  final String phone;
  final String? email;
  final String? nickname;
  final String? avatar;
  final int role;
  final int status;
  final DateTime? lastLoginAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const User({
    required this.id,
    required this.phone,
    this.email,
    this.nickname,
    this.avatar,
    required this.role,
    required this.status,
    this.lastLoginAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      nickname: json['nickname'] as String?,
      avatar: json['avatar'] as String?,
      role: json['role'] as int,
      status: json['status'] as int,
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'email': email,
      'nickname': nickname,
      'avatar': avatar,
      'role': role,
      'status': status,
      'last_login_at': lastLoginAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  String get roleName {
    switch (role) {
      case 0:
        return 'Admin';
      case 1:
        return 'Agent';
      case 2:
        return 'Installer';
      default:
        return 'User';
    }
  }
}

class LoginResponse {
  final String token;
  final String? refreshToken;
  final User user;
  final DateTime expireAt;

  const LoginResponse({
    required this.token,
    this.refreshToken,
    required this.user,
    required this.expireAt,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final expiresIn = json['expires_in'] as int?;
    return LoginResponse(
      token: (json['access_token'] ?? json['token'] ?? json['accessToken']) as String,
      refreshToken: (json['refresh_token'] ?? json['refreshToken']) as String?,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      expireAt: json['expire_at'] != null
          ? DateTime.parse(json['expire_at'] as String)
          : DateTime.now().add(Duration(seconds: expiresIn ?? 7200)),
    );
  }
}
