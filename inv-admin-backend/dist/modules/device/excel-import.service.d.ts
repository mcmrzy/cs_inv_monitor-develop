import { Repository } from 'typeorm';
import { Device } from '../../entities/device.entity';
import { Station } from '../../entities/station.entity';
export interface ExcelImportResult {
    success: number;
    failed: number;
    errors: {
        row: number;
        message: string;
    }[];
}
export declare class ExcelImportService {
    private readonly deviceRepo;
    private readonly stationRepo;
    constructor(deviceRepo: Repository<Device>, stationRepo: Repository<Station>);
    parseExcel(buffer: Buffer): any[];
    validateRows(rows: any[]): Promise<{
        valid: any[];
        errors: {
            row: number;
            message: string;
        }[];
    }>;
    bulkImport(rows: any[], userId: number, installerId: number): Promise<ExcelImportResult>;
}
