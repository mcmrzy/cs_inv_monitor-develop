import { JwtService } from '@nestjs/jwt';
import { Repository } from 'typeorm';
import { User } from '@entities/user.entity';
import { PermissionService } from '../admin/permission.service';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { SendCodeDto } from './dto/send-code.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { EmailLoginDto } from './dto/email-login.dto';
import { UpdateProfileDto } from './dto/update-profile.dto';
export interface AuthResponse {
    token: string;
    refresh_token: string;
    expire_at: string;
    permissions: string[];
    user: {
        id: number;
        phone: string;
        email: string | null;
        nickname: string | null;
        role: number;
        avatar: string | null;
    };
}
export declare class AuthService {
    private userRepo;
    private jwtService;
    private permissionService;
    private readonly BCRYPT_ROUNDS;
    private readonly verificationCodes;
    constructor(userRepo: Repository<User>, jwtService: JwtService, permissionService: PermissionService);
    private buildLoginResponse;
    validateUser(account: string, password: string): Promise<Omit<User, 'password_hash'> | null>;
    login(loginDto: LoginDto, ipAddress: string): Promise<AuthResponse>;
    refreshToken(userId: number): Promise<{
        token: string;
        refresh_token: string;
    }>;
    logout(_userId: number): Promise<void>;
    getUserProfile(userId: number): Promise<Omit<User, 'password_hash'>>;
    register(registerDto: RegisterDto): Promise<AuthResponse>;
    sendCode(sendCodeDto: SendCodeDto): Promise<{
        success: boolean;
        message: string;
    }>;
    resetPassword(resetPasswordDto: ResetPasswordDto): Promise<{
        success: boolean;
        message: string;
    }>;
    changePassword(userId: number, changePasswordDto: ChangePasswordDto): Promise<{
        success: boolean;
        message: string;
    }>;
    emailLogin(emailLoginDto: EmailLoginDto): Promise<AuthResponse>;
    updateProfile(userId: number, updateProfileDto: UpdateProfileDto): Promise<{
        success: boolean;
        message: string;
    }>;
    hashPassword(password: string): Promise<string>;
    comparePassword(password: string, hash: string): Promise<boolean>;
    private parseExpiresString;
}
