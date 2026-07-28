class User {
  final int id;
  final String phone;
  final String? email;
  final String? nickname;
  final String? avatar;
  final String? country;
  final String? region;
  final String? bio;
  final bool isSystemAdmin;
  final List<String> permissions;
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
    this.country,
    this.region,
    this.bio,
    this.isSystemAdmin = false,
    this.permissions = const [],
    required this.status,
    this.lastLoginAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final isSystemAdmin = json['is_system_admin'] == true ||
        json['isSystemAdmin'] == true ||
        (json['role'] is num && json['role'] == 0);

    final permissionsRaw = json['permissions'];
    final List<String> perms = [];
    if (permissionsRaw is List) {
      for (final p in permissionsRaw) {
        if (p is String) perms.add(p);
      }
    }

    final statusRaw = json['status'];
    final int statusVal;
    if (statusRaw is Map<String, dynamic>) {
      statusVal = (statusRaw['status_id'] as num?)?.toInt() ??
          (statusRaw['id'] as num?)?.toInt() ??
          1;
    } else {
      statusVal = (statusRaw as num?)?.toInt() ?? 1;
    }

    return User(
      id: (json['id'] as num?)?.toInt() ?? 0,
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      nickname: json['nickname'] as String?,
      avatar: json['avatar'] as String?,
      country: json['country'] as String?,
      region: json['region'] as String?,
      bio: json['bio'] as String?,
      isSystemAdmin: isSystemAdmin,
      permissions: perms,
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
      'country': country,
      'region': region,
      'bio': bio,
      'is_system_admin': isSystemAdmin,
      'permissions': permissions,
      'status': status,
      'last_login_at': lastLoginAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  String get roleName {
    if (isSystemAdmin) return 'System Admin';
    return 'Member';
  }

  bool hasPermission(String code) {
    if (isSystemAdmin) return true;
    return permissions.contains(code);
  }
}

class LoginResponse {
  final String token;
  final String? refreshToken;
  final User user;
  final DateTime expireAt;
  final List<String> permissions;

  const LoginResponse({
    required this.token,
    this.refreshToken,
    required this.user,
    required this.expireAt,
    this.permissions = const [],
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    final permsRaw = json['permissions'];
    final List<String> perms = [];
    if (permsRaw is List) {
      for (final p in permsRaw) {
        if (p is String) perms.add(p);
      }
    }
    return LoginResponse(
      token: (json['access_token'] ?? json['token'] ?? json['accessToken'])
              as String? ??
          '',
      refreshToken: (json['refresh_token'] ?? json['refreshToken']) as String?,
      user: User.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      expireAt: json['expire_at'] != null
          ? DateTime.tryParse(json['expire_at'].toString()) ??
              DateTime.now().add(Duration(seconds: expiresIn ?? 7200))
          : DateTime.now().add(Duration(seconds: expiresIn ?? 7200)),
      permissions: perms,
    );
  }
}
