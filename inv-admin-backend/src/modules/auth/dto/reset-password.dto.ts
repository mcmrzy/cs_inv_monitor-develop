import { IsString, MinLength } from 'class-validator';
import { IsStrongPassword } from '@common/validators/password.validator';

export class ResetPasswordDto {
  @IsString()
  account: string;

  @IsString()
  verify_code: string;

  @IsString()
  @MinLength(6)
  @IsStrongPassword()
  new_password: string;
}
