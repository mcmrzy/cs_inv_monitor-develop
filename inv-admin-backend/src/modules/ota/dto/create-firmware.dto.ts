import { IsString, IsOptional, IsBoolean } from 'class-validator';
import { Transform } from 'class-transformer';

export class CreateFirmwareDto {
  @IsString()
  model: string;

  @IsString()
  version: string;

  @IsOptional()
  @IsString()
  changelog?: string;

  @IsOptional()
  @Transform(({ value }) => value === 'true' || value === true)
  @IsBoolean()
  isForce?: boolean;
}
