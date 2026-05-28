"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RequirePermission = exports.REQUIRE_PERMISSION_KEY = void 0;
const common_1 = require("@nestjs/common");
exports.REQUIRE_PERMISSION_KEY = 'require_permission';
const RequirePermission = (resource, action) => (0, common_1.SetMetadata)(exports.REQUIRE_PERMISSION_KEY, { resource, action });
exports.RequirePermission = RequirePermission;
//# sourceMappingURL=require-permission.decorator.js.map