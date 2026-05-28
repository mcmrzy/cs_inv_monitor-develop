import { IsString, MinLength } from 'class-validator';

export class EmailLoginDto {
  @IsString()
  email: string;

  @IsString()
  @MinLength(6)
  password: string;
}
