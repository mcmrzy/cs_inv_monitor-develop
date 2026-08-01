// Maps role codes to their i18n translation keys.
// Roles are now derived from organization types: agent/distributor/installer/customer.
// org_admin represents the manufacturer-level super admin.
const ROLE_LABEL_KEYS: Record<string, string> = {
  org_admin: 'admin.role.orgAdmin',
  agent: 'admin.role.agent',
  distributor: 'admin.role.distributor',
  installer: 'admin.role.installer',
  customer: 'admin.role.customer',
}

type Translator = (key: string) => string

// roleLabel returns the localized label for a single role code.
// Unknown codes fall back to the raw code so nothing is hidden.
export function roleLabel(role: string, t: Translator): string {
  const code = (role ?? '').trim()
  if (!code) return ''
  const key = ROLE_LABEL_KEYS[code]
  return key ? t(key) : code
}

// roleLabels handles role strings that may contain multiple comma-separated
// codes (e.g. "org_admin,viewer") and joins their labels with " / ".
export function roleLabels(role: string, t: Translator): string {
  return (role ?? '')
    .split(',')
    .map((r) => roleLabel(r, t))
    .filter(Boolean)
    .join(' / ')
}
