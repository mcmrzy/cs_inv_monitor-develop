import { IsString, IsNotEmpty, IsOptional, IsNumber, IsBoolean, MaxLength, Min, Max } from 'class-validator';
import { Type } from 'class-transformer';

export class CreateAlertRuleDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  field_name: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(20)
  operator: string;

  @IsNumber()
  threshold_value: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  @Max(3)
  alarm_level?: number = 2;

  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  fault_code: string;

  @IsString()
  @IsNotEmpty()
  fault_message: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  device_model?: string;

  @IsOptional()
  @IsBoolean()
  is_active?: boolean = true;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  @Max(1440)
  cooldown_minutes?: number = 5;
}
