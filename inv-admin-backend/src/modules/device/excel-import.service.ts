import { Injectable, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as XLSX from 'xlsx';
import { Device } from '../../entities/device.entity';
import { Station } from '../../entities/station.entity';

export interface ExcelImportResult {
  success: number;
  failed: number;
  errors: { row: number; message: string }[];
}

@Injectable()
export class ExcelImportService {
  constructor(
    @InjectRepository(Device)
    private readonly deviceRepo: Repository<Device>,
    @InjectRepository(Station)
    private readonly stationRepo: Repository<Station>,
  ) {}

  parseExcel(buffer: Buffer): any[] {
    const workbook = XLSX.read(buffer, { type: 'buffer' });
    const sheetName = workbook.SheetNames[0];
    if (!sheetName) {
      throw new BadRequestException('Excel file is empty');
    }
    const worksheet = workbook.Sheets[sheetName];
    const rows: any[] = XLSX.utils.sheet_to_json(worksheet, { defval: '' });
    if (rows.length === 0) {
      throw new BadRequestException('No data rows found in Excel file');
    }
    return rows;
  }

  async validateRows(rows: any[]): Promise<{
    valid: any[];
    errors: { row: number; message: string }[];
  }> {
    const valid: any[] = [];
    const errors: { row: number; message: string }[] = [];

    const existingSns = new Set<string>();
    const snsInFile = new Set<string>();

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const rowNum = i + 2;
      const sn: string = (row['SN'] ?? row['sn'] ?? '').toString().trim();

      if (!sn) {
        errors.push({ row: rowNum, message: 'SN is required' });
        continue;
      }

      if (snsInFile.has(sn)) {
        errors.push({ row: rowNum, message: `Duplicate SN "${sn}" in file` });
        continue;
      }
      snsInFile.add(sn);

      const model: string = (row['Model'] ?? row['model'] ?? '').toString().trim();
      if (!model) {
        errors.push({ row: rowNum, message: 'Model is required' });
        continue;
      }

      const ratedPowerRaw = row['RatedPower(kW)'] ?? row['RatedPower'] ?? row['ratedPower'];
      const ratedPower = Number(ratedPowerRaw);
      if (ratedPowerRaw !== '' && ratedPowerRaw !== undefined && (isNaN(ratedPower) || ratedPower < 0)) {
        errors.push({ row: rowNum, message: `Invalid RatedPower: "${ratedPowerRaw}"` });
        continue;
      }

      const firmwareVersion = (row['FirmwareVersion'] ?? row['firmwareVersion'] ?? '').toString().trim();
      const hardwareVersion = (row['HardwareVersion'] ?? row['hardwareVersion'] ?? '').toString().trim();
      const stationName = (row['StationName'] ?? row['stationName'] ?? '').toString().trim();

      valid.push({
        sn,
        model,
        ratedPower: ratedPowerRaw !== '' && ratedPowerRaw !== undefined ? ratedPower : null,
        firmwareVersion: firmwareVersion || null,
        hardwareVersion: hardwareVersion || null,
        stationName: stationName || null,
        rowNum,
      });
    }

    if (valid.length > 0) {
      const sns = valid.map((v) => v.sn);
      const existing = await this.deviceRepo
        .createQueryBuilder('d')
        .select('d.sn')
        .where('d.sn IN (:...sns)', { sns })
        .getMany();
      const existingSnSet = new Set(existing.map((d) => d.sn));

      for (let i = valid.length - 1; i >= 0; i--) {
        if (existingSnSet.has(valid[i].sn)) {
          errors.push({ row: valid[i].rowNum, message: `SN "${valid[i].sn}" already exists in database` });
          valid.splice(i, 1);
        }
      }
    }

    return { valid, errors };
  }

  async bulkImport(
    rows: any[],
    userId: number,
    installerId: number,
  ): Promise<ExcelImportResult> {
    const { valid, errors } = await this.validateRows(rows);

    let successCount = 0;

    if (valid.length > 0) {
      const stationMap = new Map<string, number>();
      const stationNames = [...new Set(valid.filter((v) => v.stationName).map((v) => v.stationName))];

      if (stationNames.length > 0) {
        const stations = await this.stationRepo
          .createQueryBuilder('s')
          .where('s.name IN (:...names)', { names: stationNames })
          .getMany();
        for (const s of stations) {
          stationMap.set(s.name, s.id);
        }
      }

      const devices = valid.map((v) =>
        this.deviceRepo.create({
          sn: v.sn,
          model: v.model,
          rated_power: v.ratedPower,
          firmware_version: v.firmwareVersion,
          hardware_version: v.hardwareVersion,
          station_id: v.stationName ? (stationMap.get(v.stationName) ?? null) : null,
          user_id: userId,
          installer_id: installerId,
          status: 1,
        }),
      );

      await this.deviceRepo.save(devices);
      successCount = devices.length;
    }

    return {
      success: successCount,
      failed: errors.length,
      errors,
    };
  }
}
