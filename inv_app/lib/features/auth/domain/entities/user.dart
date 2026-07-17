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
    // API 可能返回 role 为 int（旧格式）或 Map（新格式，含 role_id/role_key 等）
    final roleRaw = json['role'];
    final int roleId;
    if (roleRaw is Map<String, dynamic>) {
      roleId = (roleRaw['role_id'] as num?)?.toInt() ?? 0;
    } else {
      roleId = (roleRaw as num?)?.toInt() ?? 0;
    }

    // status 同理，兼容 Map 和 int
    final statusRaw = json['status'];
    final int statusVal;
    if (statusRaw is Map<String, dynamic>) {
      statusVal = (statusRaw['status_id'] as num?)?.toInt() ?? (statusRaw['id'] as num?)?.toInt() ?? 1;
    } else {
      statusVal = (statusRaw as num?)?.toInt() ?? 1;
    }

    return User(
      id: (json['id'] as num?)?.toInt() ?? 0,
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      nickname: json['nickname'] as String?,
      avatar: json['avatar'] as String?,
      role: roleId,
      status: statusVal,
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.tryParse(json['last_login_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
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
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    return LoginResponse(
      token: (json['access_token'] ?? json['token'] ?? json['accessToken']) as String? ?? '',
      refreshToken: (json['refresh_token'] ?? json['refreshToken']) as String?,
      user: User.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      expireAt: json['expire_at'] != null
          ? DateTime.tryParse(json['expire_at'].toString()) ?? DateTime.now().add(Duration(seconds: expiresIn ?? 7200))
          : DateTime.now().add(Duration(seconds: expiresIn ?? 7200)),
    );
  }
}
