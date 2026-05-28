import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { Role } from '@common/enums/role.enum';

export interface DataScope {
  userId?: number;
  allowedUserIds?: number[];
  installerId?: number;
  allowedInstallerIds?: number[];
}

@Injectable()
export class DataScopeInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest();
    const user = request.user;

    if (!user) {
      return next.handle();
    }

    const scope = this.buildDataScope(user);
    request.dataScope = scope;

    return next.handle();
  }

  private buildDataScope(user: Record<string, unknown>): DataScope {
    const role = user.role as Role;
    const userId = user.id as number;

    switch (role) {
      case Role.SUPER_ADMIN:
        return {};

      case Role.AGENT:
        return {
          allowedUserIds: [],
          allowedInstallerIds: [],
        };

      case Role.INSTALLER:
        return {
          installerId: userId,
          allowedUserIds: [],
        };

      case Role.END_USER:
      default:
        return {
          userId,
        };
    }
  }
}
