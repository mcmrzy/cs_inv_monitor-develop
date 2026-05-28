import { CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Repository } from 'typeorm';
import { User } from '@entities/user.entity';
export declare class ReAuthGuard implements CanActivate {
    private reflector;
    private userRepo;
    constructor(reflector: Reflector, userRepo: Repository<User>);
    canActivate(context: ExecutionContext): Promise<boolean>;
}
