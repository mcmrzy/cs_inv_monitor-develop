export declare enum PermissionAction {
    VIEW = "view",
    CREATE = "create",
    EDIT = "edit",
    DELETE = "delete",
    EXPORT = "export",
    CONTROL = "control",
    MANAGE = "manage"
}
export declare enum PermissionResource {
    DEVICES = "devices",
    USERS = "users",
    ALERTS = "alerts",
    WORK_ORDERS = "work_orders",
    OTA = "ota",
    STATIONS = "stations",
    DASHBOARD = "dashboard",
    PARALLEL = "parallel",
    ADMIN = "admin",
    AUDIT = "audit",
    ALERT_RULES = "alert_rules",
    FIRMWARE = "firmware"
}
export declare class RolePermission {
    id: number;
    role: number;
    resource: string;
    action: string;
    is_allowed: boolean;
    updated_at: Date;
}
