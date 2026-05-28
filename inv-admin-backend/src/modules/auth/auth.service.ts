import { Injectable, UnauthorizedException, BadRequestException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcryptjs';
import { User } from '@entities/user.entity';
import { PermissionService } from '../admin/permission.service';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { SendCodeDto } from './dto/send-code.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { EmailLoginDto } from './dto/email-login.dto';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { jwtConfig } from '@config/jwt.config';

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

@Injectable()
export class AuthService {
  private readonly BCRYPT_ROUNDS = 12;
  private readonly verificationCodes = new Map<string, { code: string; expires: Date }>();

  constructor(
    @InjectRepository(User)
    private userRepo: Repository<User>,
    private jwtService: JwtService,
    private permissionService: PermissionService,
  ) {}

  private async buildLoginResponse(user: User, accessToken: string, refreshToken: string): Promise<AuthResponse> {
    const perms = await this.permissionService.getRolePermissions(user.role);
    const allowedPerms = perms.filter(p => p.is_allowed).map(p => `${p.resource}:${p.action}`);
    return {
      token: accessToken,
      refresh_token: refreshToken,
      expire_at: new Date(Date.now() + this.parseExpiresString(jwtConfig.accessTokenExpires)).toISOString(),
      permissions: allowedPerms,
      user: { id: user.id, phone: user.phone, email: user.email, nickname: user.nickname, role: user.role, avatar: user.avatar },
    };
  }

  async validateUser(account: string, password: string): Promise<Omit<User, 'password_hash'> | null> {
    const user = await this.userRepo.findOne({
      where: [{ phone: account }, { email: account }],
    });

    if (!user) {
      return null;
    }

    const isValid = await this.comparePassword(password, user.password_hash);
    if (!isValid) {
      return null;
    }

    const { password_hash: _, ...result } = user;
    return result as Omit<User, 'password_hash'>;
  }

  async login(loginDto: LoginDto, ipAddress: string): Promise<AuthResponse> {
    const user = await this.userRepo.findOne({
      where: [{ phone: loginDto.account }, { email: loginDto.account }],
    });

    if (!user) {
      throw new UnauthorizedException('账号或密码错误');
    }

    if (user.locked_until && new Date(user.locked_until) > new Date()) {
      throw new UnauthorizedException('账户已被锁定，请稍后再试');
    }

    if (user.login_fail_count >= 5 && user.locked_until && new Date(user.locked_until) > new Date()) {
      throw new UnauthorizedException('账户已被锁定，请稍后再试');
    }

    const isValid = await this.comparePassword(loginDto.password, user.password_hash);

    if (!isValid) {
      const failCount = user.login_fail_count + 1;
      const updates: Partial<User> = { login_fail_count: failCount };

      if (failCount >= 5) {
        const lockedUntil = new Date();
        lockedUntil.setMinutes(lockedUntil.getMinutes() + 30);
        updates.locked_until = lockedUntil;
      }

      await this.userRepo.update(user.id, updates);
      throw new UnauthorizedException('账号或密码错误');
    }

    const payload = { sub: user.id, user_id: user.id, role: user.role, phone: user.phone };

    const accessToken = this.jwtService.sign(payload, {
      secret: jwtConfig.secret,
      expiresIn: jwtConfig.accessTokenExpires,
    });

    const refreshToken = this.jwtService.sign(payload, {
      secret: jwtConfig.secret,
      expiresIn: jwtConfig.refreshTokenExpires,
    });

    await this.userRepo.update(user.id, {
      last_login_at: new Date(),
      last_login_ip: ipAddress,
      login_fail_count: 0,
      locked_until: undefined as unknown as Date,
    });

    return this.buildLoginResponse(user, accessToken, refreshToken);
  }

  async refreshToken(userId: number): Promise<{ token: string; refresh_token: string }> {
    const payload = { sub: userId };

    const accessToken = this.jwtService.sign(payload, {
      secret: jwtConfig.secret,
      expiresIn: jwtConfig.accessTokenExpires,
    });

    const refreshToken = this.jwtService.sign(payload, {
      secret: jwtConfig.secret,
      expiresIn: jwtConfig.refreshTokenExpires,
    });

    return { token: accessToken, refresh_token: refreshToken };
  }

  async logout(_userId: number): Promise<void> {
  }

  async getUserProfile(userId: number): Promise<Omit<User, 'password_hash'>> {
    const user = await this.userRepo.findOne({
      where: { id: userId },
      select: {
        id: true,
        phone: true,
        email: true,
        nickname: true,
        role: true,
        avatar: true,
        status: true,
        parent_id: true,
        region_id: true,
        created_at: true,
        updated_at: true,
        last_login_at: true,
        last_login_ip: true,
      } as Record<string, boolean>,
    });

    if (!user) {
      throw new UnauthorizedException('用户不存在');
    }

    return user as Omit<User, 'password_hash'>;
  }

  async register(registerDto: RegisterDto): Promise<AuthResponse> {
    if (!registerDto.phone && !registerDto.email) {
      throw new BadRequestException('手机号或邮箱至少提供一个');
    }

    const existing = await this.userRepo.findOne({
      where: [
        ...(registerDto.phone ? [{ phone: registerDto.phone }] : []),
        ...(registerDto.email ? [{ email: registerDto.email }] : []),
      ],
    });

    if (existing) {
      throw new BadRequestException('该手机号或邮箱已注册');
    }

    const hashedPassword = await this.hashPassword(registerDto.password);
    const user = this.userRepo.create({
      phone: registerDto.phone || '',
      email: registerDto.email || null,
      nickname: registerDto.nickname || null,
      password_hash: hashedPassword,
      role: 3,
    });

    await this.userRepo.save(user);

    const payload = { sub: user.id, user_id: user.id, role: user.role, phone: user.phone };
    const accessToken = this.jwtService.sign(payload, { secret: jwtConfig.secret, expiresIn: jwtConfig.accessTokenExpires });
    const refreshToken = this.jwtService.sign(payload, { secret: jwtConfig.secret, expiresIn: jwtConfig.refreshTokenExpires });

    return this.buildLoginResponse(user, accessToken, refreshToken);
  }

  async sendCode(sendCodeDto: SendCodeDto): Promise<{ success: boolean; message: string }> {
    const code = Math.random().toString().slice(2, 8);
    const expires = new Date(Date.now() + 5 * 60 * 1000);
    const key = `${sendCodeDto.type}:${sendCodeDto.target}`;
    this.verificationCodes.set(key, { code, expires });

    console.log(`[验证码] ${key}: ${code}`);

    return { success: true, message: '验证码已发送' };
  }

  async resetPassword(resetPasswordDto: ResetPasswordDto): Promise<{ success: boolean; message: string }> {
    const key = `reset_password:${resetPasswordDto.account}`;
    const cached = this.verificationCodes.get(key);

    if (!cached || cached.expires < new Date() || cached.code !== resetPasswordDto.verify_code) {
      throw new BadRequestException('验证码无效或已过期');
    }

    const user = await this.userRepo.findOne({
      where: [
        { phone: resetPasswordDto.account },
        { email: resetPasswordDto.account },
      ],
    });

    if (!user) {
      throw new BadRequestException('该账号不存在');
    }

    const hashedPassword = await this.hashPassword(resetPasswordDto.new_password);
    await this.userRepo.update(user.id, { password_hash: hashedPassword });

    this.verificationCodes.delete(key);

    return { success: true, message: '密码重置成功' };
  }

  async changePassword(userId: number, changePasswordDto: ChangePasswordDto): Promise<{ success: boolean; message: string }> {
    const user = await this.userRepo.findOne({ where: { id: userId } });

    if (!user) {
      throw new UnauthorizedException('用户不存在');
    }

    const isValid = await this.comparePassword(changePasswordDto.old_password, user.password_hash);
    if (!isValid) {
      throw new BadRequestException('原密码错误');
    }

    const hashedPassword = await this.hashPassword(changePasswordDto.new_password);
    await this.userRepo.update(userId, { password_hash: hashedPassword });

    return { success: true, message: '密码修改成功' };
  }

  async emailLogin(emailLoginDto: EmailLoginDto): Promise<AuthResponse> {
    const user = await this.userRepo.findOne({
      where: { email: emailLoginDto.email },
    });

    if (!user) {
      throw new UnauthorizedException('邮箱或密码错误');
    }

    if (user.locked_until && new Date(user.locked_until) > new Date()) {
      throw new UnauthorizedException('账户已被锁定，请稍后再试');
    }

    const isValid = await this.comparePassword(emailLoginDto.password, user.password_hash);
    if (!isValid) {
      throw new UnauthorizedException('邮箱或密码错误');
    }

    const payload = { sub: user.id, user_id: user.id, role: user.role, phone: user.phone };
    const accessToken = this.jwtService.sign(payload, { secret: jwtConfig.secret, expiresIn: jwtConfig.accessTokenExpires });
    const refreshToken = this.jwtService.sign(payload, { secret: jwtConfig.secret, expiresIn: jwtConfig.refreshTokenExpires });

    await this.userRepo.update(user.id, {
      last_login_at: new Date(),
      login_fail_count: 0,
      locked_until: undefined as unknown as Date,
    });

    return this.buildLoginResponse(user, accessToken, refreshToken);
  }

  async updateProfile(userId: number, updateProfileDto: UpdateProfileDto): Promise<{ success: boolean; message: string }> {
    const updates: Partial<User> = {};

    if (updateProfileDto.nickname !== undefined) {
      updates.nickname = updateProfileDto.nickname;
    }
    if (updateProfileDto.avatar !== undefined) {
      updates.avatar = updateProfileDto.avatar;
    }

    if (Object.keys(updates).length > 0) {
      await this.userRepo.update(userId, updates);
    }

    return { success: true, message: '资料更新成功' };
  }

  async hashPassword(password: string): Promise<string> {
    return bcrypt.hash(password, this.BCRYPT_ROUNDS);
  }

  async comparePassword(password: string, hash: string): Promise<boolean> {
    return bcrypt.compare(password, hash);
  }

  private parseExpiresString(expires: string): number {
    const match = expires.match(/^(\d+)([smhd])$/);
    if (!match) {
      return 15 * 60 * 1000;
    }
    const value = parseInt(match[1], 10);
    const unit = match[2];
    switch (unit) {
      case 's':
        return value * 1000;
      case 'm':
        return value * 60 * 1000;
      case 'h':
        return value * 60 * 60 * 1000;
      case 'd':
        return value * 24 * 60 * 60 * 1000;
      default:
        return 15 * 60 * 1000;
    }
  }
}
