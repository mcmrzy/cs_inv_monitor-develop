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
exports.ReAuthGuard = void 0;
const common_1 = require("@nestjs/common");
const core_1 = require("@nestjs/core");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const bcrypt = require("bcryptjs");
const user_entity_1 = require("../../entities/user.entity");
const require_reauth_decorator_1 = require("../decorators/require-reauth.decorator");
let ReAuthGuard = class ReAuthGuard {
    constructor(reflector, userRepo) {
        this.reflector = reflector;
        this.userRepo = userRepo;
    }
    async canActivate(context) {
        const requireReauth = this.reflector.getAllAndOverride(require_reauth_decorator_1.REQUIRE_REAUTH_KEY, [context.getHandler(), context.getClass()]);
        if (!requireReauth) {
            return true;
        }
        const request = context.switchToHttp().getRequest();
        const user = request.user;
        const reAuthPassword = request.headers['x-re-auth-password'];
        if (!user || !user.id) {
            throw new common_1.ForbiddenException('未认证的用户');
        }
        if (!reAuthPassword) {
            throw new common_1.ForbiddenException('敏感操作需要重新验证密码，请在请求头中提供 x-re-auth-password');
        }
        const dbUser = await this.userRepo.findOne({
            where: { id: user.id },
            select: ['id', 'password_hash'],
        });
        if (!dbUser) {
            throw new common_1.ForbiddenException('用户不存在');
        }
        const isValid = await bcrypt.compare(reAuthPassword, dbUser.password_hash);
        if (!isValid) {
            throw new common_1.ForbiddenException('密码验证失败，无法执行此操作');
        }
        return true;
    }
};
exports.ReAuthGuard = ReAuthGuard;
exports.ReAuthGuard = ReAuthGuard = __decorate([
    (0, common_1.Injectable)(),
    __param(1, (0, typeorm_1.InjectRepository)(user_entity_1.User)),
    __metadata("design:paramtypes", [core_1.Reflector,
        typeorm_2.Repository])
], ReAuthGuard);
//# sourceMappingURL=re-auth.guard.js.map