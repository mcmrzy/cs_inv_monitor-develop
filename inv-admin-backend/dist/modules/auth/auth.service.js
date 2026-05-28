"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthService = void 0;
const common_1 = require("@nestjs/common");
const jwt_1 = require("@nestjs/jwt");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const bcrypt = require("bcryptjs");
const user_entity_1 = require("../../entities/user.entity");
const permission_service_1 = require("../admin/permission.service");
const jwt_config_1 = require("../../config/jwt.config");
let AuthService = class AuthService {
    constructor(userRepo, jwtService, permissionService) {
        this.userRepo = userRepo;
        this.jwtService = jwtService;
        this.permissionService = permissionService;
        this.BCRYPT_ROUNDS = 12;
        this.verificationCodes = new Map();
    }
    async buildLoginResponse(user, accessToken, refreshToken) {
        const perms = await this.permissionService.getRolePermissions(user.role);
        const allowedPerms = perms.filter(p => p.is_allowed).map(p => `${p.resource}:${p.action}`);
        return {
            token: accessToken,
            refresh_token: refreshToken,
            expire_at: new Date(Date.now() + this.parseExpiresString(jwt_config_1.jwtConfig.accessTokenExpires)).toISOString(),
            permissions: allowedPerms,
            user: { id: user.id, phone: user.phone, email: user.email, nickname: user.nickname, role: user.role, avatar: user.avatar },
        };
    }
    async validateUser(account, password) {
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
        return result;
    }
    async login(loginDto, ipAddress) {
        const user = await this.userRepo.findOne({
            where: [{ phone: loginDto.account }, { email: loginDto.account }],
        });
        if (!user) {
            throw new common_1.UnauthorizedException('账号或密码错误');
        }
        if (user.locked_until && new Date(user.locked_until) > new Date()) {
            throw new common_1.UnauthorizedException('账户已被锁定，请稍后再试');
        }
        if (user.login_fail_count >= 5 && user.locked_until && new Date(user.locked_until) > new Date()) {
            throw new common_1.UnauthorizedException('账户已被锁定，请稍后再试');
        }
        const isValid = await this.comparePassword(loginDto.password, user.password_hash);
        if (!isValid) {
            const failCount = user.login_fail_count + 1;
            const updates = { login_fail_count: failCount };
            if (failCount >= 5) {
                const lockedUntil = new Date();
                lockedUntil.setMinutes(lockedUntil.getMinutes() + 30);
                updates.locked_until = lockedUntil;
            }
            await this.userRepo.update(user.id, updates);
            throw new common_1.UnauthorizedException('账号或密码错误');
        }
        const payload = { sub: user.id, user_id: user.id, role: user.role, phone: user.phone };
        const accessToken = this.jwtService.sign(payload, {
            secret: jwt_config_1.jwtConfig.secret,
            expiresIn: jwt_config_1.jwtConfig.accessTokenExpires,
        });
        const refreshToken = this.jwtService.sign(payload, {
            secret: jwt_config_1.jwtConfig.secret,
            expiresIn: jwt_config_1.jwtConfig.refreshTokenExpires,
        });
        await this.userRepo.update(user.id, {
            last_login_at: new Date(),
            last_login_ip: ipAddress,
            login_fail_count: 0,
            locked_until: undefined,
        });
        return this.buildLoginResponse(user, accessToken, refreshToken);
    }
    async refreshToken(userId) {
        const payload = { sub: userId };
        const accessToken = this.jwtService.sign(payload, {
            secret: jwt_config_1.jwtConfig.secret,
            expiresIn: jwt_config_1.jwtConfig.accessTokenExpires,
        });
        const refreshToken = this.jwtService.sign(payload, {
            secret: jwt_config_1.jwtConfig.secret,
            expiresIn: jwt_config_1.jwtConfig.refreshTokenExpires,
        });
        return { token: accessToken, refresh_token: refreshToken };
    }
    async logout(_userId) {
    }
    async getUserProfile(userId) {
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
            },
        });
        if (!user) {
            throw new common_1.UnauthorizedException('用户不存在');
        }
        return user;
    }
    async register(registerDto) {
        if (!registerDto.phone && !registerDto.email) {
            throw new common_1.BadRequestException('手机号或邮箱至少提供一个');
        }
        const existing = await this.userRepo.findOne({
            where: [
                ...(registerDto.phone ? [{ phone: registerDto.phone }] : []),
                ...(registerDto.email ? [{ email: registerDto.email }] : []),
            ],
        });
        if (existing) {
            throw new common_1.BadRequestException('该手机号或邮箱已注册');
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
        const accessToken = this.jwtService.sign(payload, { secret: jwt_config_1.jwtConfig.secret, expiresIn: jwt_config_1.jwtConfig.accessTokenExpires });
        const refreshToken = this.jwtService.sign(payload, { secret: jwt_config_1.jwtConfig.secret, expiresIn: jwt_config_1.jwtConfig.refreshTokenExpires });
        return this.buildLoginResponse(user, accessToken, refreshToken);
    }
    async sendCode(sendCodeDto) {
        const code = Math.random().toString().slice(2, 8);
        const expires = new Date(Date.now() + 5 * 60 * 1000);
        const key = `${sendCodeDto.type}:${sendCodeDto.target}`;
        this.verificationCodes.set(key, { code, expires });
        console.log(`[验证码] ${key}: ${code}`);
        return { success: true, message: '验证码已发送' };
    }
    async resetPassword(resetPasswordDto) {
        const key = `reset_password:${resetPasswordDto.account}`;
        const cached = this.verificationCodes.get(key);
        if (!cached || cached.expires < new Date() || cached.code !== resetPasswordDto.verify_code) {
            throw new common_1.BadRequestException('验证码无效或已过期');
        }
        const user = await this.userRepo.findOne({
            where: [
                { phone: resetPasswordDto.account },
                { email: resetPasswordDto.account },
            ],
        });
        if (!user) {
            throw new common_1.BadRequestException('该账号不存在');
        }
        const hashedPassword = await this.hashPassword(resetPasswordDto.new_password);
        await this.userRepo.update(user.id, { password_hash: hashedPassword });
        this.verificationCodes.delete(key);
        return { success: true, message: '密码重置成功' };
    }
    async changePassword(userId, changePasswordDto) {
        const user = await this.userRepo.findOne({ where: { id: userId } });
        if (!user) {
            throw new common_1.UnauthorizedException('用户不存在');
        }
        const isValid = await this.comparePassword(changePasswordDto.old_password, user.password_hash);
        if (!isValid) {
            throw new common_1.BadRequestException('原密码错误');
        }
        const hashedPassword = await this.hashPassword(changePasswordDto.new_password);
        await this.userRepo.update(userId, { password_hash: hashedPassword });
        return { success: true, message: '密码修改成功' };
    }
    async emailLogin(emailLoginDto) {
        const user = await this.userRepo.findOne({
            where: { email: emailLoginDto.email },
        });
        if (!user) {
            throw new common_1.UnauthorizedException('邮箱或密码错误');
        }
        if (user.locked_until && new Date(user.locked_until) > new Date()) {
            throw new common_1.UnauthorizedException('账户已被锁定，请稍后再试');
        }
        const isValid = await this.comparePassword(emailLoginDto.password, user.password_hash);
        if (!isValid) {
            throw new common_1.UnauthorizedException('邮箱或密码错误');
        }
        const payload = { sub: user.id, user_id: user.id, role: user.role, phone: user.phone };
        const accessToken = this.jwtService.sign(payload, { secret: jwt_config_1.jwtConfig.secret, expiresIn: jwt_config_1.jwtConfig.accessTokenExpires });
        const refreshToken = this.jwtService.sign(payload, { secret: jwt_config_1.jwtConfig.secret, expiresIn: jwt_config_1.jwtConfig.refreshTokenExpires });
        await this.userRepo.update(user.id, {
            last_login_at: new Date(),
            login_fail_count: 0,
            locked_until: undefined,
        });
        return this.buildLoginResponse(user, accessToken, refreshToken);
    }
    async updateProfile(userId, updateProfileDto) {
        const updates = {};
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
    async hashPassword(password) {
        return bcrypt.hash(password, this.BCRYPT_ROUNDS);
    }
    async comparePassword(password, hash) {
        return bcrypt.compare(password, hash);
    }
    parseExpiresString(expires) {
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
};
exports.AuthService = AuthService;
exports.AuthService = AuthService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(user_entity_1.User)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        jwt_1.JwtService,
        permission_service_1.PermissionService])
], AuthService);
//# sourceMappingURL=auth.service.js.map