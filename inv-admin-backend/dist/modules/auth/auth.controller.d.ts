import { Request } from 'express';
import { JwtService } from '@nestjs/jwt';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { RegisterDto } from './dto/register.dto';
import { SendCodeDto } from './dto/send-code.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { EmailLoginDto } from './dto/email-login.dto';
import { UpdateProfileDto } from './dto/update-profile.dto';
export declare class AuthController {
    private readonly authService;
    private readonly jwtService;
    constructor(authService: AuthService, jwtService: JwtService);
    login(loginDto: LoginDto, req: Request): Promise<import("./auth.service").AuthResponse>;
    emailLogin(emailLoginDto: EmailLoginDto): Promise<import("./auth.service").AuthResponse>;
    register(registerDto: RegisterDto): Promise<import("./auth.service").AuthResponse>;
    sendCode(sendCodeDto: SendCodeDto): Promise<{
        success: boolean;
        message: string;
    }>;
    refresh(dto: RefreshTokenDto): Promise<{
        token: string;
        refresh_token: string;
    }>;
    resetPassword(resetPasswordDto: ResetPasswordDto): Promise<{
        success: boolean;
        message: string;
    }>;
    changePassword(userId: number, changePasswordDto: ChangePasswordDto): Promise<{
        success: boolean;
        message: string;
    }>;
    logout(userId: number): Promise<{
        success: boolean;
        message: string;
    }>;
    profile(userId: number): Promise<Omit<import("../../entities/user.entity").User, "password_hash">>;
    updateProfile(userId: number, updateProfileDto: UpdateProfileDto): Promise<{
        success: boolean;
        message: string;
    }>;
}
