import { IsString, MinLength } from 'class-validator';
import { IsStrongPassword } from '@common/validators/password.validator';

export class ChangePasswordDto {
  @IsString()
  old_password: string;

  @IsString()
  @MinLength(6)
  @IsStrongPassword()
  new_password: string;
}
