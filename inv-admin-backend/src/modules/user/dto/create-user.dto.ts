import { IsString, IsOptional, IsEmail, MinLength, IsInt, IsIn } from 'class-validator';
import { IsStrongPassword } from '@common/validators/password.validator';

export class CreateUserDto {
  @IsString()
  phone: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsString()
  @IsStrongPassword()
  password: string;

  @IsOptional()
  @IsString()
  nickname?: string;

  @IsInt()
  @IsIn([0, 1, 2, 3])
  role: number;

  @IsOptional()
  @IsInt()
  parentId?: number;
}

export class UpdateUserDto {
  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  nickname?: string;

  @IsOptional()
  @IsInt()
  @IsIn([0, 1, 2, 3])
  role?: number;

  @IsOptional()
  @IsInt()
  parentId?: number;

  @IsOptional()
  @IsInt()
  regionId?: number;

  @IsOptional()
  @IsInt()
  @IsIn([0, 1])
  status?: number;
}

export class QueryUserDto {
  @IsOptional()
  page?: number = 1;

  @IsOptional()
  pageSize?: number = 20;

  @IsOptional()
  @IsString()
  keyword?: string;

  @IsOptional()
  @IsInt()
  @IsIn([0, 1, 2, 3])
  role?: number;
}

export class ResetPasswordDto {
  @IsString()
  @IsStrongPassword()
  newPassword: string;
}
