-- 059: Multi-level channel organizations, memberships, scoped permissions,
-- resource grants, quotas, invitations, and migration quarantine.

CREATE TABLE IF NOT EXISTS organizations (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL,
    parent_id BIGINT,
    org_type VARCHAR(32) NOT NULL
        CHECK (org_type IN ('manufacturer', 'agent', 'distributor', 'customer', 'service_partner')),
    code VARCHAR(64),
    name VARCHAR(160) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'disabled', 'quarantined')),
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT organizations_root_shape CHECK (
        (parent_id IS NULL AND org_type = 'manufacturer' AND id = root_tenant_id)
        OR
        (parent_id IS NOT NULL AND org_type <> 'manufacturer' AND id <> root_tenant_id)
    ),
    CONSTRAINT uq_organizations_root_id UNIQUE (root_tenant_id, id),
    CONSTRAINT fk_organizations_parent_same_root
        FOREIGN KEY (root_tenant_id, parent_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_organizations_root_code
    ON organizations(root_tenant_id, LOWER(code))
    WHERE code IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_organizations_parent
    ON organizations(root_tenant_id, parent_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_organizations_type_status
    ON organizations(root_tenant_id, org_type, status) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS tenant_roots (
    root_tenant_id BIGINT PRIMARY KEY,
    organization_id BIGINT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT tenant_roots_identity CHECK (root_tenant_id = organization_id),
    CONSTRAINT fk_tenant_roots_manufacturer
        FOREIGN KEY (root_tenant_id, organization_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS organization_closure (
    root_tenant_id BIGINT NOT NULL,
    ancestor_id BIGINT NOT NULL,
    descendant_id BIGINT NOT NULL,
    depth INTEGER NOT NULL CHECK (depth >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (root_tenant_id, ancestor_id, descendant_id),
    CONSTRAINT organization_closure_self_depth CHECK (
        (ancestor_id = descendant_id AND depth = 0)
        OR (ancestor_id <> descendant_id AND depth > 0)
    ),
    CONSTRAINT fk_closure_tenant_root
        FOREIGN KEY (root_tenant_id) REFERENCES tenant_roots(root_tenant_id) ON DELETE RESTRICT,
    CONSTRAINT fk_closure_ancestor_same_root
        FOREIGN KEY (root_tenant_id, ancestor_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_closure_descendant_same_root
        FOREIGN KEY (root_tenant_id, descendant_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_organization_closure_descendant
    ON organization_closure(root_tenant_id, descendant_id, depth, ancestor_id);
CREATE INDEX IF NOT EXISTS idx_organization_closure_ancestor
    ON organization_closure(root_tenant_id, ancestor_id, depth, descendant_id);

CREATE OR REPLACE FUNCTION guard_organization_closure_mutation()
RETURNS TRIGGER AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'organization closure is maintained only by governed organization workflows'
            USING ERRCODE = '55000';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION guard_organization_closure_mutation() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_organization_closure_guard ON organization_closure;
CREATE TRIGGER trg_organization_closure_guard
    BEFORE INSERT OR UPDATE OR DELETE ON organization_closure
    FOR EACH ROW EXECUTE FUNCTION guard_organization_closure_mutation();

CREATE OR REPLACE FUNCTION validate_organization_hierarchy()
RETURNS TRIGGER AS $$
DECLARE
    parent_type VARCHAR(32);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        NEW.parent_id IS DISTINCT FROM OLD.parent_id
        OR NEW.root_tenant_id IS DISTINCT FROM OLD.root_tenant_id
        OR NEW.org_type IS DISTINCT FROM OLD.org_type
    ) THEN
        RAISE EXCEPTION 'direct organization hierarchy/type changes are forbidden; use the governed move workflow'
            USING ERRCODE = '55000';
    END IF;

    IF NEW.org_type = 'manufacturer' THEN
        IF NEW.parent_id IS NOT NULL OR NEW.id <> NEW.root_tenant_id THEN
            RAISE EXCEPTION 'manufacturer must be a self-identified root tenant'
                USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.parent_id IS NULL OR NEW.parent_id = NEW.id THEN
        RAISE EXCEPTION 'non-root organization requires a different parent'
            USING ERRCODE = '23514';
    END IF;

    SELECT org_type INTO parent_type
    FROM public.organizations
    WHERE root_tenant_id = NEW.root_tenant_id
      AND id = NEW.parent_id
      AND deleted_at IS NULL
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'organization parent does not exist in root tenant %', NEW.root_tenant_id
            USING ERRCODE = '23503';
    END IF;

    IF NOT (
        (NEW.org_type = 'agent' AND parent_type = 'manufacturer')
        OR (NEW.org_type = 'distributor' AND parent_type = 'agent')
        OR (NEW.org_type = 'customer' AND parent_type = 'distributor')
        OR (NEW.org_type = 'service_partner' AND parent_type IN ('manufacturer', 'agent', 'distributor'))
    ) THEN
        RAISE EXCEPTION 'illegal organization hierarchy: % cannot be parent of %', parent_type, NEW.org_type
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;

CREATE OR REPLACE FUNCTION maintain_organization_insert_relations()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.org_type = 'manufacturer' THEN
        INSERT INTO public.tenant_roots(root_tenant_id, organization_id)
        VALUES (NEW.root_tenant_id, NEW.id)
        ON CONFLICT (root_tenant_id) DO NOTHING;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM public.tenant_roots WHERE root_tenant_id = NEW.root_tenant_id) THEN
            RAISE EXCEPTION 'root tenant % is not registered', NEW.root_tenant_id
                USING ERRCODE = '23503';
        END IF;
        INSERT INTO public.organization_closure(root_tenant_id, ancestor_id, descendant_id, depth)
        SELECT NEW.root_tenant_id, ancestor_id, NEW.id, depth + 1
        FROM public.organization_closure
        WHERE root_tenant_id = NEW.root_tenant_id
          AND descendant_id = NEW.parent_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'parent organization % has no closure facts', NEW.parent_id
                USING ERRCODE = '23503';
        END IF;
    END IF;

    INSERT INTO public.organization_closure(root_tenant_id, ancestor_id, descendant_id, depth)
    VALUES (NEW.root_tenant_id, NEW.id, NEW.id, 0);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION validate_organization_hierarchy() FROM PUBLIC;
REVOKE ALL ON FUNCTION maintain_organization_insert_relations() FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON organization_closure FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_organizations_validate_hierarchy ON organizations;
CREATE TRIGGER trg_organizations_validate_hierarchy
    BEFORE INSERT OR UPDATE OF parent_id, root_tenant_id, org_type ON organizations
    FOR EACH ROW EXECUTE FUNCTION validate_organization_hierarchy();

DROP TRIGGER IF EXISTS trg_organizations_insert_relations ON organizations;
CREATE TRIGGER trg_organizations_insert_relations
    AFTER INSERT ON organizations
    FOR EACH ROW EXECUTE FUNCTION maintain_organization_insert_relations();

CREATE TABLE IF NOT EXISTS organization_memberships (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL,
    organization_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'disabled', 'expired', 'revoked')),
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_memberships_root_org_id UNIQUE (root_tenant_id, organization_id, id),
    CONSTRAINT uq_memberships_root_org_user_id UNIQUE (root_tenant_id, organization_id, user_id, id),
    CONSTRAINT fk_memberships_organization_same_root
        FOREIGN KEY (root_tenant_id, organization_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_memberships_active_org_user
    ON organization_memberships(root_tenant_id, organization_id, user_id)
    WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_memberships_user_status
    ON organization_memberships(user_id, status);

CREATE TABLE IF NOT EXISTS membership_role_assignments (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL,
    organization_id BIGINT NOT NULL,
    membership_id BIGINT NOT NULL,
    role_code VARCHAR(64) NOT NULL
        CHECK (role_code IN ('org_admin', 'channel_manager', 'operator', 'installer', 'after_sales', 'viewer', 'finance', 'api_client')),
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'revoked', 'expired')),
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    assigned_by BIGINT REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_role_assignments_root_org_id UNIQUE (root_tenant_id, organization_id, id),
    CONSTRAINT fk_role_assignments_membership_same_org
        FOREIGN KEY (root_tenant_id, organization_id, membership_id)
        REFERENCES organization_memberships(root_tenant_id, organization_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_role_assignments_active_role
    ON membership_role_assignments(membership_id, role_code)
    WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_role_assignments_membership_fk
    ON membership_role_assignments(root_tenant_id, organization_id, membership_id);

CREATE TABLE IF NOT EXISTS role_permission_grants (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL,
    organization_id BIGINT NOT NULL,
    role_assignment_id BIGINT NOT NULL,
    permission_code VARCHAR(128) NOT NULL
        CHECK (permission_code ~ '^[a-z][a-z0-9_]*:[a-z][a-z0-9_]*$'),
    data_scope VARCHAR(40) NOT NULL
        CHECK (data_scope IN ('self', 'organization', 'organization_and_descendants', 'assigned_resources', 'explicit_resources')),
    scope_definition JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(scope_definition) = 'object'),
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_permission_grants_assignment_same_org
        FOREIGN KEY (root_tenant_id, organization_id, role_assignment_id)
        REFERENCES membership_role_assignments(root_tenant_id, organization_id, id) ON DELETE RESTRICT,
    CONSTRAINT uq_permission_grant_assignment_code UNIQUE (role_assignment_id, permission_code)
);

CREATE INDEX IF NOT EXISTS idx_permission_grants_permission_scope
    ON role_permission_grants(root_tenant_id, organization_id, permission_code, data_scope);

CREATE TABLE IF NOT EXISTS authorization_resources (
    root_tenant_id BIGINT NOT NULL,
    organization_id BIGINT NOT NULL,
    resource_type VARCHAR(40) NOT NULL CHECK (BTRIM(resource_type) <> ''),
    resource_id TEXT NOT NULL CHECK (BTRIM(resource_id) <> ''),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'transferring', 'retired')),
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (root_tenant_id, resource_type, resource_id),
    CONSTRAINT uq_authorization_resources_owner UNIQUE (root_tenant_id, organization_id, resource_type, resource_id),
    CONSTRAINT fk_authorization_resources_org_same_root
        FOREIGN KEY (root_tenant_id, organization_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_authorization_resources_org
    ON authorization_resources(root_tenant_id, organization_id, resource_type, status);

CREATE TABLE IF NOT EXISTS resource_grants (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL,
    organization_id BIGINT NOT NULL,
    resource_type VARCHAR(40) NOT NULL,
    resource_id TEXT NOT NULL,
    subject_type VARCHAR(24) NOT NULL CHECK (subject_type IN ('organization', 'user')),
    subject_organization_id BIGINT NOT NULL,
    subject_user_id BIGINT,
    subject_membership_id BIGINT,
    permissions TEXT[] NOT NULL CHECK (cardinality(permissions) > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'revoked', 'expired')),
    valid_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    created_by BIGINT REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT resource_grants_subject_shape CHECK (
        (subject_type = 'organization' AND subject_user_id IS NULL AND subject_membership_id IS NULL)
        OR (subject_type = 'user' AND subject_user_id IS NOT NULL AND subject_membership_id IS NOT NULL)
    ),
    CONSTRAINT resource_grants_validity CHECK (expires_at IS NULL OR expires_at > valid_from),
    CONSTRAINT fk_resource_grants_resource_same_root
        FOREIGN KEY (root_tenant_id, organization_id, resource_type, resource_id)
        REFERENCES authorization_resources(root_tenant_id, organization_id, resource_type, resource_id) ON DELETE RESTRICT,
    CONSTRAINT fk_resource_grants_subject_org_same_root
        FOREIGN KEY (root_tenant_id, subject_organization_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_resource_grants_subject_user_membership_same_org
        FOREIGN KEY (root_tenant_id, subject_organization_id, subject_user_id, subject_membership_id)
        REFERENCES organization_memberships(root_tenant_id, organization_id, user_id, id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_resource_grants_resource
    ON resource_grants(root_tenant_id, resource_type, resource_id, status);
CREATE INDEX IF NOT EXISTS idx_resource_grants_subject_org
    ON resource_grants(root_tenant_id, subject_organization_id, status);
CREATE INDEX IF NOT EXISTS idx_resource_grants_resource_owner_fk
    ON resource_grants(root_tenant_id, organization_id, resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_resource_grants_subject_membership_fk
    ON resource_grants(root_tenant_id, subject_organization_id, subject_user_id, subject_membership_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_resource_grants_active_subject
    ON resource_grants(
        root_tenant_id, organization_id, resource_type, resource_id,
        subject_type, subject_organization_id,
        COALESCE(subject_user_id, 0), COALESCE(subject_membership_id, 0)
    ) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS organization_quotas (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL,
    organization_id BIGINT NOT NULL,
    resource_type VARCHAR(64) NOT NULL
        CHECK (resource_type IN (
            'members', 'direct_child_organizations', 'descendant_organizations',
            'inventory_devices', 'claimed_devices', 'stations', 'pending_invitations',
            'concurrent_exports', 'api_requests_per_minute'
        )),
    quota_limit BIGINT NOT NULL CHECK (quota_limit >= 0),
    inherited_from_organization_id BIGINT,
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_organization_quotas_org_same_root
        FOREIGN KEY (root_tenant_id, organization_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_organization_quotas_inherited_same_root
        FOREIGN KEY (root_tenant_id, inherited_from_organization_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT uq_organization_quota UNIQUE (root_tenant_id, organization_id, resource_type),
    CONSTRAINT fk_organization_quotas_inherited_quota
        FOREIGN KEY (root_tenant_id, inherited_from_organization_id, resource_type)
        REFERENCES organization_quotas(root_tenant_id, organization_id, resource_type)
        ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS organization_quota_usage (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL,
    organization_id BIGINT NOT NULL,
    resource_type VARCHAR(64) NOT NULL,
    used_count BIGINT NOT NULL DEFAULT 0 CHECK (used_count >= 0),
    reserved_count BIGINT NOT NULL DEFAULT 0 CHECK (reserved_count >= 0),
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_quota_usage_quota
        FOREIGN KEY (root_tenant_id, organization_id, resource_type)
        REFERENCES organization_quotas(root_tenant_id, organization_id, resource_type) ON DELETE RESTRICT,
    CONSTRAINT uq_organization_quota_usage UNIQUE (root_tenant_id, organization_id, resource_type)
);

CREATE INDEX IF NOT EXISTS idx_organization_quotas_inherited_fk
    ON organization_quotas(root_tenant_id, inherited_from_organization_id)
    WHERE inherited_from_organization_id IS NOT NULL;

CREATE OR REPLACE FUNCTION validate_organization_quota_usage()
RETURNS TRIGGER AS $$
DECLARE
    limit_value BIGINT;
BEGIN
    SELECT quota_limit INTO limit_value
    FROM public.organization_quotas
    WHERE root_tenant_id = NEW.root_tenant_id
      AND organization_id = NEW.organization_id
      AND resource_type = NEW.resource_type
    FOR UPDATE;
    IF NOT FOUND OR NEW.used_count + NEW.reserved_count > limit_value THEN
        RAISE EXCEPTION 'organization quota exceeded'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;

DROP TRIGGER IF EXISTS trg_organization_quota_usage_limit ON organization_quota_usage;
CREATE TRIGGER trg_organization_quota_usage_limit
    BEFORE INSERT OR UPDATE OF root_tenant_id, organization_id, resource_type, used_count, reserved_count
    ON organization_quota_usage
    FOR EACH ROW EXECUTE FUNCTION validate_organization_quota_usage();

CREATE OR REPLACE FUNCTION validate_organization_quota_limit()
RETURNS TRIGGER AS $$
DECLARE
    current_total BIGINT;
    inherited_limit BIGINT;
    inherited_child_max BIGINT;
    quota_org_type VARCHAR(32);
BEGIN
	SELECT org_type INTO quota_org_type
	FROM public.organizations
	WHERE root_tenant_id = NEW.root_tenant_id
	  AND id = NEW.organization_id;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'quota organization does not exist' USING ERRCODE = '23503';
	END IF;

	IF quota_org_type = 'manufacturer' AND NEW.inherited_from_organization_id IS NOT NULL THEN
		RAISE EXCEPTION 'manufacturer quota must not inherit from another organization'
			USING ERRCODE = '23514';
	ELSIF quota_org_type <> 'manufacturer' AND NEW.inherited_from_organization_id IS NULL THEN
		RAISE EXCEPTION 'non-root quota must inherit an ancestor limit'
			USING ERRCODE = '23514';
	END IF;

	IF NEW.inherited_from_organization_id IS NOT NULL THEN
		IF NOT EXISTS (
			SELECT 1 FROM public.organization_closure
			WHERE root_tenant_id = NEW.root_tenant_id
			  AND ancestor_id = NEW.inherited_from_organization_id
			  AND descendant_id = NEW.organization_id
			  AND depth > 0
		) THEN
			RAISE EXCEPTION 'quota inheritance must reference an ancestor organization'
				USING ERRCODE = '23514';
		END IF;

		SELECT quota_limit INTO inherited_limit
		FROM public.organization_quotas
		WHERE root_tenant_id = NEW.root_tenant_id
		  AND organization_id = NEW.inherited_from_organization_id
		  AND resource_type = NEW.resource_type
		FOR SHARE;
		IF NOT FOUND OR NEW.quota_limit > inherited_limit THEN
			RAISE EXCEPTION 'descendant quota cannot exceed inherited ancestor limit'
				USING ERRCODE = '23514';
		END IF;

		SELECT MIN(q.quota_limit) INTO inherited_limit
		FROM public.organization_closure c
		JOIN public.organization_quotas q
		  ON q.root_tenant_id = c.root_tenant_id
		 AND q.organization_id = c.ancestor_id
		 AND q.resource_type = NEW.resource_type
		WHERE c.root_tenant_id = NEW.root_tenant_id
		  AND c.descendant_id = NEW.organization_id
		  AND c.depth > 0;
		IF inherited_limit IS NULL OR NEW.quota_limit > inherited_limit THEN
			RAISE EXCEPTION 'descendant quota cannot exceed the strictest ancestor limit'
				USING ERRCODE = '23514';
		END IF;
	END IF;

	SELECT MAX(q.quota_limit) INTO inherited_child_max
	FROM public.organization_closure c
	JOIN public.organization_quotas q
	  ON q.root_tenant_id = c.root_tenant_id
	 AND q.organization_id = c.descendant_id
	 AND q.resource_type = NEW.resource_type
	WHERE c.root_tenant_id = NEW.root_tenant_id
	  AND c.ancestor_id = NEW.organization_id
	  AND c.depth > 0
	  AND q.id <> NEW.id;
	IF inherited_child_max IS NOT NULL AND inherited_child_max > NEW.quota_limit THEN
		RAISE EXCEPTION 'quota limit cannot be lower than an inherited descendant limit'
			USING ERRCODE = '23514';
	END IF;

    SELECT used_count + reserved_count INTO current_total
    FROM public.organization_quota_usage
    WHERE root_tenant_id = NEW.root_tenant_id
      AND organization_id = NEW.organization_id
      AND resource_type = NEW.resource_type;
    IF FOUND AND current_total > NEW.quota_limit THEN
        RAISE EXCEPTION 'quota limit cannot be lower than current usage and reservations'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;

DROP TRIGGER IF EXISTS trg_organization_quota_limit ON organization_quotas;
CREATE TRIGGER trg_organization_quota_limit
    BEFORE INSERT OR UPDATE OF root_tenant_id, organization_id, resource_type, quota_limit, inherited_from_organization_id
    ON organization_quotas
    FOR EACH ROW EXECUTE FUNCTION validate_organization_quota_limit();

CREATE OR REPLACE FUNCTION consume_organization_quota(
    p_root_tenant_id BIGINT,
    p_organization_id BIGINT,
    p_resource_type VARCHAR,
    p_used_delta BIGINT,
    p_reserved_delta BIGINT
) RETURNS VOID AS $$
DECLARE
    limit_value BIGINT;
BEGIN
    SELECT quota_limit INTO limit_value
    FROM public.organization_quotas
    WHERE root_tenant_id = p_root_tenant_id
      AND organization_id = p_organization_id
      AND resource_type = p_resource_type
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'organization quota is not configured' USING ERRCODE = '23503';
    END IF;

    INSERT INTO public.organization_quota_usage(root_tenant_id, organization_id, resource_type)
    VALUES (p_root_tenant_id, p_organization_id, p_resource_type)
    ON CONFLICT (root_tenant_id, organization_id, resource_type) DO NOTHING;

    UPDATE public.organization_quota_usage
    SET used_count = used_count + p_used_delta,
        reserved_count = reserved_count + p_reserved_delta,
        version = version + 1,
        updated_at = NOW()
    WHERE root_tenant_id = p_root_tenant_id
      AND organization_id = p_organization_id
      AND resource_type = p_resource_type
      AND used_count + p_used_delta >= 0
      AND reserved_count + p_reserved_delta >= 0
      AND used_count + reserved_count + p_used_delta + p_reserved_delta <= limit_value;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'organization quota exceeded' USING ERRCODE = '23514';
    END IF;
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION validate_organization_quota_usage() FROM PUBLIC;
REVOKE ALL ON FUNCTION validate_organization_quota_limit() FROM PUBLIC;
REVOKE ALL ON FUNCTION consume_organization_quota(BIGINT, BIGINT, VARCHAR, BIGINT, BIGINT) FROM PUBLIC;

CREATE TABLE IF NOT EXISTS invitations (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL,
    organization_id BIGINT NOT NULL,
    recipient VARCHAR(254) NOT NULL,
    normalized_recipient VARCHAR(254) GENERATED ALWAYS AS (LOWER(BTRIM(recipient))) STORED,
    token_key_id VARCHAR(64) NOT NULL,
    token_digest BYTEA NOT NULL CHECK (octet_length(token_digest) >= 32),
    role_assignments JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(role_assignments) = 'array'),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'rejected', 'expired', 'revoked')),
    invited_by BIGINT REFERENCES users(id) ON DELETE RESTRICT,
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT invitation_expiry_after_creation CHECK (expires_at > created_at),
    CONSTRAINT fk_invitations_organization_same_root
        FOREIGN KEY (root_tenant_id, organization_id)
        REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT uq_invitations_digest UNIQUE (token_key_id, token_digest)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_invitations_pending_recipient
    ON invitations(root_tenant_id, organization_id, normalized_recipient)
    WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_invitations_expiry
    ON invitations(status, expires_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_invitations_organization_fk
    ON invitations(root_tenant_id, organization_id);

CREATE TABLE IF NOT EXISTS channel_migration_quarantine (
    id BIGSERIAL PRIMARY KEY,
    source_table VARCHAR(128) NOT NULL,
    source_key TEXT NOT NULL,
    reason_code VARCHAR(64) NOT NULL,
    reason_detail TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(payload) = 'object'),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'resolved', 'ignored')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    UNIQUE(source_table, source_key, reason_code)
);
