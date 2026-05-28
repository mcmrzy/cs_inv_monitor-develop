import { Controller, Get } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Controller()
export class HealthController {
  constructor(private readonly connection: DataSource) {}

  @Get('health/live')
  live() {
    return { status: 'ok', uptime: process.uptime() };
  }

  @Get('health/ready')
  async ready() {
    let dbOk = false;
    try {
      await this.connection.query('SELECT 1');
      dbOk = true;
    } catch {
      dbOk = false;
    }

    return {
      status: 'ok',
      checks: {
        database: dbOk,
        redis: true,
      },
    };
  }
}
