import { CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
export declare const IP_WHITELIST_KEY = "ip_whitelist";
export declare class IpWhitelistGuard implements CanActivate {
    private reflector;
    private allowedIps;
    constructor(reflector: Reflector);
    canActivate(context: ExecutionContext): boolean;
    private ipInCidr;
    private ipToNumber;
}
export declare const IpWhitelist: () => import("@nestjs/common").CustomDecorator<string>;
