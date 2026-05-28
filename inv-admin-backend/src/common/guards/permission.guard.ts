import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from '@common/decorators/roles.decorator';
import { REQUIRE_PERMISSION_KEY } from '@common/decorators/require-permission.decorator';
import { PermissionService } from '../../modules/admin/permission.service';

@Injectable()
export class PermissionGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private permissionService: PermissionService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const requiredRoles = this.reflector.getAllAndOverride<number[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (requiredRoles) {
      const { user } = context.switchToHttp().getRequest();
      if (!user) throw new ForbiddenException('未认证');
      if (!requiredRoles.includes(user.role))
        throw new ForbiddenException('权限不足');
    }

    const requiredPermission = this.reflector.getAllAndOverride<{ resource: string; action: string }>(
      REQUIRE_PERMISSION_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (requiredPermission) {
      const { user } = context.switchToHttp().getRequest();
      if (!user) throw new ForbiddenException('未认证');
      const hasPerm = await this.permissionService.hasPermission(
        user.role,
        requiredPermission.resource,
        requiredPermission.action,
      );
      if (!hasPerm)
        throw new ForbiddenException(
          `需要 ${requiredPermission.resource}:${requiredPermission.action} 权限`,
        );
    }

    return true;
  }
}
