"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RequireReauth = exports.REQUIRE_REAUTH_KEY = void 0;
const common_1 = require("@nestjs/common");
exports.REQUIRE_REAUTH_KEY = 'require_reauth';
const RequireReauth = () => (0, common_1.SetMetadata)(exports.REQUIRE_REAUTH_KEY, true);
exports.RequireReauth = RequireReauth;
//# sourceMappingURL=require-reauth.decorator.js.map