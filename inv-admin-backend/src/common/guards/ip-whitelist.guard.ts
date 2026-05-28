import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';

export const IP_WHITELIST_KEY = 'ip_whitelist';

@Injectable()
export class IpWhitelistGuard implements CanActivate {
  private allowedIps: string[];

  constructor(private reflector: Reflector) {
    this.allowedIps = (process.env.ADMIN_IP_WHITELIST ?? '')
      .split(',')
      .map((ip) => ip.trim())
      .filter((ip) => ip.length > 0);
  }

  canActivate(context: ExecutionContext): boolean {
    const whitelistEnabled = this.reflector.getAllAndOverride<boolean>(
      IP_WHITELIST_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (!whitelistEnabled || this.allowedIps.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const clientIp: string =
      request.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
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
      throw new ForbiddenException('您的IP地址不在白名单中，无法访问此资源');
    }

    return true;
  }

  private ipInCidr(ip: string, cidr: string): boolean {
    const [range, bitsStr] = cidr.split('/');
    const bits = parseInt(bitsStr, 10);
    if (isNaN(bits)) return false;

    const ipNum = this.ipToNumber(ip);
    const rangeNum = this.ipToNumber(range);
    const mask = ~(2 ** (32 - bits) - 1);

    return (ipNum & mask) === (rangeNum & mask);
  }

  private ipToNumber(ip: string): number {
    return ip
      .split('.')
      .reduce((acc, octet) => (acc << 8) + parseInt(octet, 10), 0) >>> 0;
  }
}

import { SetMetadata } from '@nestjs/common';

export const IpWhitelist = () => SetMetadata(IP_WHITELIST_KEY, true);
