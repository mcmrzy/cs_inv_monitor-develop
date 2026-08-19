-- 成员转移审批制：成员跨组织转移由"直接转移"改为审批流
-- 发起人（源组织 org_admin / 系统管理员）创建 pending 申请，
-- 目标组织 org_admin / 系统管理员审批通过后才真正执行 membership 转移。
-- 说明：membership_id 不设外键 —— 审批通过后旧 membership 行会被物理删除，
-- 而审批记录需保留作为审计凭证。
CREATE TABLE IF NOT EXISTS member_transfer_requests (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL,
    membership_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    from_org_id BIGINT NOT NULL,
    to_org_id BIGINT NOT NULL,
    initiator_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
    reason TEXT,
    reject_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_mtr_tenant_root
        FOREIGN KEY (root_tenant_id) REFERENCES tenant_roots(root_tenant_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mtr_from_org_same_root
        FOREIGN KEY (root_tenant_id, from_org_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_mtr_to_org_same_root
        FOREIGN KEY (root_tenant_id, to_org_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT
);

-- 审批工作台按状态倒序拉取
CREATE INDEX IF NOT EXISTS idx_mtr_status_created
    ON member_transfer_requests(status, created_at DESC);
-- 同一 membership 防重复 pending 申请
CREATE INDEX IF NOT EXISTS idx_mtr_membership_pending
    ON member_transfer_requests(membership_id) WHERE status = 'pending';
-- 目标组织管理员查看待自己审批的申请
CREATE INDEX IF NOT EXISTS idx_mtr_to_org
    ON member_transfer_requests(to_org_id);
