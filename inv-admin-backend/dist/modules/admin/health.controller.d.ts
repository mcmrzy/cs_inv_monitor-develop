import { DataSource } from 'typeorm';
export declare class HealthController {
    private readonly connection;
    constructor(connection: DataSource);
    live(): {
        status: string;
        uptime: number;
    };
    ready(): Promise<{
        status: string;
        checks: {
            database: boolean;
            redis: boolean;
        };
    }>;
}
