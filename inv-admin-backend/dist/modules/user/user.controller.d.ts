import { UserService } from './user.service';
import { CreateUserDto, UpdateUserDto, QueryUserDto, ResetPasswordDto } from './dto/create-user.dto';
export declare class UserController {
    private readonly userService;
    constructor(userService: UserService);
    findAll(query: QueryUserDto, currentUser: any): Promise<{
        items: import("../../entities/user.entity").User[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    create(dto: CreateUserDto, currentUser: any): Promise<import("../../entities/user.entity").User>;
    findById(id: number, currentUser: any): Promise<import("../../entities/user.entity").User>;
    update(id: number, dto: UpdateUserDto, currentUser: any): Promise<import("../../entities/user.entity").User>;
    disable(id: number): Promise<void>;
    resetPassword(id: number, dto: ResetPasswordDto): Promise<void>;
}
