"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SanitizeInterceptor = void 0;
const common_1 = require("@nestjs/common");
let SanitizeInterceptor = class SanitizeInterceptor {
    intercept(context, next) {
        const request = context.switchToHttp().getRequest();
        if (request.body && typeof request.body === 'object') {
            this.sanitizeObject(request.body);
        }
        return next.handle();
    }
    sanitizeObject(obj) {
        for (const key of Object.keys(obj)) {
            const value = obj[key];
            if (typeof value === 'string') {
                obj[key] = this.escapeHtml(value.trim());
            }
            else if (Array.isArray(value)) {
                obj[key] = value.map((item) => {
                    if (typeof item === 'string') {
                        return this.escapeHtml(item.trim());
                    }
                    if (typeof item === 'object' && item !== null) {
                        this.sanitizeObject(item);
                    }
                    return item;
                });
            }
            else if (typeof value === 'object' && value !== null) {
                this.sanitizeObject(value);
            }
        }
    }
    escapeHtml(str) {
        return str
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#x27;');
    }
};
exports.SanitizeInterceptor = SanitizeInterceptor;
exports.SanitizeInterceptor = SanitizeInterceptor = __decorate([
    (0, common_1.Injectable)()
], SanitizeInterceptor);
//# sourceMappingURL=sanitize.interceptor.js.map