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

/// 组织成员角色枚举（与后端 membership_role_assignments.role_code 一致）
enum OrgMemberRole {
  orgAdmin, // 组织管理员
  agent, // 代理商
  distributor, // 分销商
  installer, // 安装商
  customer, // 终端用户
}

extension OrgMemberRoleExtension on OrgMemberRole {
  String get displayName {
    switch (this) {
      case OrgMemberRole.orgAdmin:
        return '组织管理员';
      case OrgMemberRole.agent:
        return '代理商';
      case OrgMemberRole.distributor:
        return '分销商';
      case OrgMemberRole.installer:
        return '安装商';
      case OrgMemberRole.customer:
        return '终端用户';
    }
  }

  String get apiValue {
    switch (this) {
      case OrgMemberRole.orgAdmin:
        return 'org_admin';
      case OrgMemberRole.agent:
        return 'agent';
      case OrgMemberRole.distributor:
        return 'distributor';
      case OrgMemberRole.installer:
        return 'installer';
      case OrgMemberRole.customer:
        return 'customer';
    }
  }

  static OrgMemberRole fromApiValue(String value) {
    switch (value.toLowerCase()) {
      case 'org_admin':
        return OrgMemberRole.orgAdmin;
      case 'agent':
        return OrgMemberRole.agent;
      case 'distributor':
        return OrgMemberRole.distributor;
      case 'installer':
        return OrgMemberRole.installer;
      case 'customer':
        return OrgMemberRole.customer;
      default:
        return OrgMemberRole.customer;
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

/// 组织邀请实体（与后端 invitations 列表项对齐）
class OrganizationInvitation {
  final int id;
  final int? organizationId;
  final String? organization;
  final String email;
  final List<String> roleCodes;
  final String status; // pending/accepted/rejected/expired/revoked
  final String? expiresAt;
  final String? createdAt;
  final String? inviterName;
  final String? inviteLink; // 仅创建响应中返回一次（相对路径）

  const OrganizationInvitation({
    required this.id,
    this.organizationId,
    this.organization,
    required this.email,
    this.roleCodes = const [],
    required this.status,
    this.expiresAt,
    this.createdAt,
    this.inviterName,
    this.inviteLink,
  });

  factory OrganizationInvitation.fromJson(Map<String, dynamic> json) {
    return OrganizationInvitation(
      id: json['id'] as int,
      organizationId: json['organization_id'] as int?,
      organization: json['organization'] as String?,
      email: (json['email'] as String?) ?? '',
      roleCodes: (json['role_codes'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      status: (json['status'] as String?) ?? 'pending',
      expiresAt: json['expires_at'] as String?,
      createdAt: json['created_at'] as String?,
      inviterName: json['inviter_name'] as String?,
      inviteLink: json['invite_link'] as String?,
    );
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
