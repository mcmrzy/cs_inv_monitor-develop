import { Repository } from 'typeorm';
import { User } from '../../entities/user.entity';
import { CreateUserDto, UpdateUserDto, QueryUserDto } from './dto/create-user.dto';
export declare class UserService {
    private readonly userRepo;
    constructor(userRepo: Repository<User>);
    private getRoleName;
    private canManageRole;
    private isDescendantOf;
    create(dto: CreateUserDto, createdBy: any): Promise<User>;
    findAll(query: QueryUserDto, currentUser: any): Promise<{
        items: User[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    findById(id: number, currentUser: any): Promise<User>;
    update(id: number, dto: UpdateUserDto, currentUser: any): Promise<User>;
    disable(id: number): Promise<void>;
    resetPassword(id: number, newPassword: string): Promise<void>;
    getSubUserIds(userId: number): Promise<number[]>;
}
