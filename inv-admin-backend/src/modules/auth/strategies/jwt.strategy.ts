import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from '@entities/user.entity';
import { jwtConfig } from '@config/jwt.config';

export interface JwtPayload {
  sub?: number;
  user_id?: number;
  role?: number;
  phone?: string;
  iat?: number;
  exp?: number;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(
    @InjectRepository(User)
    private userRepo: Repository<User>,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: jwtConfig.secret,
    });
  }

  async validate(payload: JwtPayload): Promise<Omit<User, 'password_hash'>> {
    const userId = payload.sub ?? payload.user_id;
    if (!userId) {
      throw new UnauthorizedException('无效的Token');
    }

    const user = await this.userRepo.findOne({
      where: { id: userId },
      select: {
        id: true,
        phone: true,
        email: true,
        nickname: true,
        role: true,
        avatar: true,
        status: true,
        parent_id: true,
        region_id: true,
      } as Record<string, boolean>,
    });

    if (!user) {
      throw new UnauthorizedException('用户不存在或已被删除');
    }

    if (user.status !== 1) {
      throw new UnauthorizedException('账户已被禁用');
    }

    return user;
  }
}
