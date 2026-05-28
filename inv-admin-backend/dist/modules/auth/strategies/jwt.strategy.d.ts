import { Strategy } from 'passport-jwt';
import { Repository } from 'typeorm';
import { User } from '@entities/user.entity';
export interface JwtPayload {
    sub?: number;
    user_id?: number;
    role?: number;
    phone?: string;
    iat?: number;
    exp?: number;
}
declare const JwtStrategy_base: new (...args: any[]) => Strategy;
export declare class JwtStrategy extends JwtStrategy_base {
    private userRepo;
    constructor(userRepo: Repository<User>);
    validate(payload: JwtPayload): Promise<Omit<User, 'password_hash'>>;
}
export {};
