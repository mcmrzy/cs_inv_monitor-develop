import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcryptjs';
import { User } from '@entities/user.entity';
import { REQUIRE_REAUTH_KEY } from '@common/decorators/require-reauth.decorator';

@Injectable()
export class ReAuthGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    @InjectRepository(User)
    private userRepo: Repository<User>,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const requireReauth = this.reflector.getAllAndOverride<boolean>(
      REQUIRE_REAUTH_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (!requireReauth) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const user = request.user as Record<string, unknown> | undefined;
    const reAuthPassword = request.headers['x-re-auth-password'] as string | undefined;

    if (!user || !user.id) {
      throw new ForbiddenException('未认证的用户');
    }

    if (!reAuthPassword) {
      throw new ForbiddenException('敏感操作需要重新验证密码，请在请求头中提供 x-re-auth-password');
    }

    const dbUser = await this.userRepo.findOne({
      where: { id: user.id as number },
      select: ['id', 'password_hash'],
    });

    if (!dbUser) {
      throw new ForbiddenException('用户不存在');
    }

    const isValid = await bcrypt.compare(reAuthPassword, dbUser.password_hash);
    if (!isValid) {
      throw new ForbiddenException('密码验证失败，无法执行此操作');
    }

    return true;
  }
}
