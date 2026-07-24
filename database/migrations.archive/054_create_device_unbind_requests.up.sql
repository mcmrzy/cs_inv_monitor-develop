-- 050: Create device_unbind_requests table for device unbind request workflow.
--
-- Users can submit a request to unbind a device from their account.  Admins
-- review the request and either approve or reject it.  A partial unique index
-- ensures only one pending request exists per device at a time.

CREATE TABLE device_unbind_requests (
    id              BIGSERIAL PRIMARY KEY,
    device_sn       VARCHAR(50) NOT NULL,
    requested_by    BIGINT NOT NULL,
    reason          TEXT,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewed_by     BIGINT,
    review_comment  TEXT,
    reviewed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_unbind_requests_status ON device_unbind_requests(status);
CREATE INDEX idx_unbind_requests_device_sn ON device_unbind_requests(device_sn);

-- Partial unique index: only one pending request per device at a time.
CREATE UNIQUE INDEX idx_unbind_requests_pending ON device_unbind_requests(device_sn) WHERE status = 'pending';

COMMENT ON TABLE device_unbind_requests IS '设备解绑申请表，用户提交解绑请求由管理员审核';
COMMENT ON COLUMN device_unbind_requests.status IS '审核状态: pending | approved | rejected';
