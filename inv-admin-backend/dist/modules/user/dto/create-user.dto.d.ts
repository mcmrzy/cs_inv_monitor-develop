export declare class CreateUserDto {
    phone: string;
    email?: string;
    password: string;
    nickname?: string;
    role: number;
    parentId?: number;
}
export declare class UpdateUserDto {
    phone?: string;
    email?: string;
    nickname?: string;
    role?: number;
    parentId?: number;
    regionId?: number;
    status?: number;
}
export declare class QueryUserDto {
    page?: number;
    pageSize?: number;
    keyword?: string;
    role?: number;
}
export declare class ResetPasswordDto {
    newPassword: string;
}
