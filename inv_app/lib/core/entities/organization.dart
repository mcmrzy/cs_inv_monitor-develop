/// 组织实体
class Organization {
  final int id;
  final String name;
  final String? description;
  final int memberCount;
  final int deviceCount;
  final String? createdAt;
  final String? updatedAt;

  const Organization({
    required this.id,
    required this.name,
    this.description,
    this.memberCount = 0,
    this.deviceCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory Organization.fromJson(Map<String, dynamic> json) {
    return Organization(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      memberCount: json['member_count'] as int? ?? 0,
      deviceCount: json['device_count'] as int? ?? 0,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'member_count': memberCount,
      'device_count': deviceCount,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Organization copyWith({
    int? id,
    String? name,
    String? description,
    int? memberCount,
    int? deviceCount,
    String? createdAt,
    String? updatedAt,
  }) {
    return Organization(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      memberCount: memberCount ?? this.memberCount,
      deviceCount: deviceCount ?? this.deviceCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 组织成员角色枚举
enum OrgMemberRole {
  owner, // 拥有者
  admin, // 管理员
  member, // 普通成员
  viewer, // 查看者
}

extension OrgMemberRoleExtension on OrgMemberRole {
  String get displayName {
    switch (this) {
      case OrgMemberRole.owner:
        return '拥有者';
      case OrgMemberRole.admin:
        return '管理员';
      case OrgMemberRole.member:
        return '成员';
      case OrgMemberRole.viewer:
        return '查看者';
    }
  }

  String get apiValue {
    switch (this) {
      case OrgMemberRole.owner:
        return 'owner';
      case OrgMemberRole.admin:
        return 'admin';
      case OrgMemberRole.member:
        return 'member';
      case OrgMemberRole.viewer:
        return 'viewer';
    }
  }

  static OrgMemberRole fromApiValue(String value) {
    switch (value.toLowerCase()) {
      case 'owner':
        return OrgMemberRole.owner;
      case 'admin':
        return OrgMemberRole.admin;
      case 'member':
        return OrgMemberRole.member;
      case 'viewer':
        return OrgMemberRole.viewer;
      default:
        return OrgMemberRole.member;
    }
  }
}

/// 组织成员实体
class OrganizationMember {
  final int userId;
  final String email;
  final String? phone;
  final String? nickname;
  final OrgMemberRole role;
  final bool pending;
  final String? invitedAt;
  final String? acceptedAt;

  const OrganizationMember({
    required this.userId,
    required this.email,
    this.phone,
    this.nickname,
    required this.role,
    this.pending = false,
    this.invitedAt,
    this.acceptedAt,
  });

  factory OrganizationMember.fromJson(Map<String, dynamic> json) {
    return OrganizationMember(
      userId: json['user_id'] as int,
      email: json['email'] as String,
      phone: json['phone'] as String?,
      nickname: json['nickname'] as String?,
      role: OrgMemberRoleExtension.fromApiValue(json['role'] as String),
      pending: json['pending'] as bool? ?? false,
      invitedAt: json['invited_at'] as String?,
      acceptedAt: json['accepted_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'email': email,
      'phone': phone,
      'nickname': nickname,
      'role': role.apiValue,
      'pending': pending,
      'invited_at': invitedAt,
      'accepted_at': acceptedAt,
    };
  }
}

/// 组织邀请实体
class OrganizationInvitation {
  final int id;
  final int organizationId;
  final String email;
  final OrgMemberRole role;
  final String? invitedBy;
  final String? invitedByName;
  final String? expiresAt;
  final bool used;
  final String? usedAt;
  final String? inviteLink;

  const OrganizationInvitation({
    required this.id,
    required this.organizationId,
    required this.email,
    required this.role,
    this.invitedBy,
    this.invitedByName,
    this.expiresAt,
    this.used = false,
    this.usedAt,
    this.inviteLink,
  });

  factory OrganizationInvitation.fromJson(Map<String, dynamic> json) {
    return OrganizationInvitation(
      id: json['id'] as int,
      organizationId: json['organization_id'] as int,
      email: json['email'] as String,
      role: OrgMemberRoleExtension.fromApiValue(json['role'] as String),
      invitedBy: json['invited_by'] as String?,
      invitedByName: json['invited_by_name'] as String?,
      expiresAt: json['expires_at'] as String?,
      used: json['used'] as bool? ?? false,
      usedAt: json['used_at'] as String?,
      inviteLink: json['invite_link'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'email': email,
      'role': role.apiValue,
      'invited_by': invitedBy,
      'invited_by_name': invitedByName,
      'expires_at': expiresAt,
      'used': used,
      'used_at': usedAt,
      'invite_link': inviteLink,
    };
  }
}

/// 设备转移请求实体
class DeviceTransferRequest {
  final int id;
  final String deviceSn;
  final String deviceModel;
  final int sourceOrgId;
  final String? sourceOrgName;
  final int targetOrgId;
  final String? targetOrgName;
  final String requesterEmail;
  final String? requesterName;
  final String? reason;
  final String status; // pending, approved, rejected
  final String? requestedAt;
  final String? approvedAt;
  final String? approvedBy;
  final String? rejectionReason;

  const DeviceTransferRequest({
    required this.id,
    required this.deviceSn,
    required this.deviceModel,
    required this.sourceOrgId,
    this.sourceOrgName,
    required this.targetOrgId,
    this.targetOrgName,
    required this.requesterEmail,
    this.requesterName,
    this.reason,
    required this.status,
    this.requestedAt,
    this.approvedAt,
    this.approvedBy,
    this.rejectionReason,
  });

  factory DeviceTransferRequest.fromJson(Map<String, dynamic> json) {
    return DeviceTransferRequest(
      id: json['id'] as int,
      deviceSn: json['device_sn'] as String,
      deviceModel: json['device_model'] as String,
      sourceOrgId: json['source_org_id'] as int,
      sourceOrgName: json['source_org_name'] as String?,
      targetOrgId: json['target_org_id'] as int,
      targetOrgName: json['target_org_name'] as String?,
      requesterEmail: json['requester_email'] as String,
      requesterName: json['requester_name'] as String?,
      reason: json['reason'] as String?,
      status: json['status'] as String,
      requestedAt: json['requested_at'] as String?,
      approvedAt: json['approved_at'] as String?,
      approvedBy: json['approved_by'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_sn': deviceSn,
      'device_model': deviceModel,
      'source_org_id': sourceOrgId,
      'source_org_name': sourceOrgName,
      'target_org_id': targetOrgId,
      'target_org_name': targetOrgName,
      'requester_email': requesterEmail,
      'requester_name': requesterName,
      'reason': reason,
      'status': status,
      'requested_at': requestedAt,
      'approved_at': approvedAt,
      'approved_by': approvedBy,
      'rejection_reason': rejectionReason,
    };
  }
}
