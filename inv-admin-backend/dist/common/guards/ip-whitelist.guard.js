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
Object.defineProperty(exports, "__esModule", { value: true });
exports.IpWhitelist = exports.IpWhitelistGuard = exports.IP_WHITELIST_KEY = void 0;
const common_1 = require("@nestjs/common");
const core_1 = require("@nestjs/core");
exports.IP_WHITELIST_KEY = 'ip_whitelist';
let IpWhitelistGuard = class IpWhitelistGuard {
    constructor(reflector) {
        this.reflector = reflector;
        this.allowedIps = (process.env.ADMIN_IP_WHITELIST ?? '')
            .split(',')
            .map((ip) => ip.trim())
            .filter((ip) => ip.length > 0);
    }
    canActivate(context) {
        const whitelistEnabled = this.reflector.getAllAndOverride(exports.IP_WHITELIST_KEY, [context.getHandler(), context.getClass()]);
        if (!whitelistEnabled || this.allowedIps.length === 0) {
            return true;
        }
        const request = context.switchToHttp().getRequest();
        const clientIp = request.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
            request.ip ||
            request.connection?.remoteAddress ||
            '';
        const normalizedIp = clientIp.replace('::ffff:', '');
        const isAllowed = this.allowedIps.some((allowedIp) => {
            if (allowedIp.includes('/')) {
                return this.ipInCidr(normalizedIp, allowedIp);
            }
            return normalizedIp === allowedIp;
        });
        if (!isAllowed) {
            throw new common_1.ForbiddenException('您的IP地址不在白名单中，无法访问此资源');
        }
        return true;
    }
    ipInCidr(ip, cidr) {
        const [range, bitsStr] = cidr.split('/');
        const bits = parseInt(bitsStr, 10);
        if (isNaN(bits))
            return false;
        const ipNum = this.ipToNumber(ip);
        const rangeNum = this.ipToNumber(range);
        const mask = ~(2 ** (32 - bits) - 1);
        return (ipNum & mask) === (rangeNum & mask);
    }
    ipToNumber(ip) {
        return ip
            .split('.')
            .reduce((acc, octet) => (acc << 8) + parseInt(octet, 10), 0) >>> 0;
    }
};
exports.IpWhitelistGuard = IpWhitelistGuard;
exports.IpWhitelistGuard = IpWhitelistGuard = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [core_1.Reflector])
], IpWhitelistGuard);
const common_2 = require("@nestjs/common");
const IpWhitelist = () => (0, common_2.SetMetadata)(exports.IP_WHITELIST_KEY, true);
exports.IpWhitelist = IpWhitelist;
//# sourceMappingURL=ip-whitelist.guard.js.map