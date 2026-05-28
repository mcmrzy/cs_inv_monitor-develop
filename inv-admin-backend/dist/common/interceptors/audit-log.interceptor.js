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
exports.AuditLogInterceptor = void 0;
const common_1 = require("@nestjs/common");
const core_1 = require("@nestjs/core");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const operators_1 = require("rxjs/operators");
const audit_log_entity_1 = require("../../entities/audit-log.entity");
const audit_log_decorator_1 = require("../decorators/audit-log.decorator");
const MAX_BODY_LENGTH = 1000;
let AuditLogInterceptor = class AuditLogInterceptor {
    constructor(auditLogRepo, reflector) {
        this.auditLogRepo = auditLogRepo;
        this.reflector = reflector;
    }
    intercept(context, next) {
        const auditLogMeta = this.reflector.get(audit_log_decorator_1.AUDIT_LOG_KEY, context.getHandler());
        if (!auditLogMeta) {
            return next.handle();
        }
        const request = context.switchToHttp().getRequest();
        const user = request.user;
        return next.handle().pipe((0, operators_1.tap)(() => {
            this.createAuditLog(auditLogMeta, request, user, false).catch(() => { });
        }), (0, operators_1.catchError)((error) => {
            this.createAuditLog({ ...auditLogMeta, action: `${auditLogMeta.action}_FAILED` }, request, user, true).catch(() => { });
            throw error;
        }));
    }
    async createAuditLog(meta, request, user, failed) {
        try {
            const method = request.method || '';
            const body = request.body;
            const params = request.params;
            const query = request.query;
            let details = {};
            if (['POST', 'PUT', 'PATCH'].includes(method) && body) {
                const bodyStr = JSON.stringify(body);
                if (bodyStr.length > MAX_BODY_LENGTH) {
                    details = {
                        body_truncated: true,
                        body_preview: bodyStr.substring(0, MAX_BODY_LENGTH) + '...',
                    };
                }
                else {
                    details = { body };
                }
            }
            if (params && Object.keys(params).length > 0) {
                details.params = params;
            }
            if (query && Object.keys(query).length > 0) {
                const queryCopy = { ...query };
                delete queryCopy.password;
                delete queryCopy.token;
                if (Object.keys(queryCopy).length > 0) {
                    details.query = queryCopy;
                }
            }
            if (failed) {
                details.failed = true;
            }
            const resourceId = params?.id ??
                params?.sn ??
                params?.taskId ??
                params?.ruleId ??
                undefined;
            const auditLog = this.auditLogRepo.create({
                user_id: user?.id ?? 0,
                username: user?.nickname ?? 'unknown',
                action: meta.action,
                resource: meta.resource,
                resource_id: resourceId,
                details,
                ip_address: request.ip ?? null,
            });
            await this.auditLogRepo.save(auditLog);
        }
        catch {
        }
    }
};
exports.AuditLogInterceptor = AuditLogInterceptor;
exports.AuditLogInterceptor = AuditLogInterceptor = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(audit_log_entity_1.AuditLog)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        core_1.Reflector])
], AuditLogInterceptor);
//# sourceMappingURL=audit-log.interceptor.js.map