import { IsString, IsIn } from 'class-validator';

export class SendCodeDto {
  @IsString()
  target: string;

  @IsString()
  @IsIn(['register', 'reset_password', 'change_phone', 'change_email'])
  type: string;
}
