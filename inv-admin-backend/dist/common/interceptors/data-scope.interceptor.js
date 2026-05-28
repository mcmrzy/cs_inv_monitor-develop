"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DataScopeInterceptor = void 0;
const common_1 = require("@nestjs/common");
const role_enum_1 = require("../enums/role.enum");
let DataScopeInterceptor = class DataScopeInterceptor {
    intercept(context, next) {
        const request = context.switchToHttp().getRequest();
        const user = request.user;
        if (!user) {
            return next.handle();
        }
        const scope = this.buildDataScope(user);
        request.dataScope = scope;
        return next.handle();
    }
    buildDataScope(user) {
        const role = user.role;
        const userId = user.id;
        switch (role) {
            case role_enum_1.Role.SUPER_ADMIN:
                return {};
            case role_enum_1.Role.AGENT:
                return {
                    allowedUserIds: [],
                    allowedInstallerIds: [],
                };
            case role_enum_1.Role.INSTALLER:
                return {
                    installerId: userId,
                    allowedUserIds: [],
                };
            case role_enum_1.Role.END_USER:
            default:
                return {
                    userId,
                };
        }
    }
};
exports.DataScopeInterceptor = DataScopeInterceptor;
exports.DataScopeInterceptor = DataScopeInterceptor = __decorate([
    (0, common_1.Injectable)()
], DataScopeInterceptor);
//# sourceMappingURL=data-scope.interceptor.js.map