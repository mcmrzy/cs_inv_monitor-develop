export declare class User {
    id: number;
    phone: string;
    email: string | null;
    password_hash: string;
    nickname: string | null;
    avatar: string | null;
    role: number;
    parent_id: number | null;
    region_id: number | null;
    status: number;
    last_login_at: Date;
    last_login_ip: string | null;
    login_fail_count: number;
    locked_until: Date | null;
    created_at: Date;
    updated_at: Date;
    deleted_at: Date;
}
