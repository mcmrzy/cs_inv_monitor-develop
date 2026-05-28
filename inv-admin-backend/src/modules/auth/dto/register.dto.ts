import { IsString, MinLength, IsOptional } from 'class-validator';
import { IsStrongPassword } from '@common/validators/password.validator';

export class RegisterDto {
  @IsString()
  @IsOptional()
  phone?: string;

  @IsString()
  @IsOptional()
  email?: string;

  @IsString()
  @MinLength(6)
  @IsStrongPassword()
  password: string;

  @IsString()
  @IsOptional()
  nickname?: string;

  @IsString()
  @IsOptional()
  verify_code?: string;
}
