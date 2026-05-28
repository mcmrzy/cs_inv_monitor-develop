"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ExcelImportService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const XLSX = require("xlsx");
const device_entity_1 = require("../../entities/device.entity");
const station_entity_1 = require("../../entities/station.entity");
let ExcelImportService = class ExcelImportService {
    constructor(deviceRepo, stationRepo) {
        this.deviceRepo = deviceRepo;
        this.stationRepo = stationRepo;
    }
    parseExcel(buffer) {
        const workbook = XLSX.read(buffer, { type: 'buffer' });
        const sheetName = workbook.SheetNames[0];
        if (!sheetName) {
            throw new common_1.BadRequestException('Excel file is empty');
        }
        const worksheet = workbook.Sheets[sheetName];
        const rows = XLSX.utils.sheet_to_json(worksheet, { defval: '' });
        if (rows.length === 0) {
            throw new common_1.BadRequestException('No data rows found in Excel file');
        }
        return rows;
    }
    async validateRows(rows) {
        const valid = [];
        const errors = [];
        const existingSns = new Set();
        const snsInFile = new Set();
        for (let i = 0; i < rows.length; i++) {
            const row = rows[i];
            const rowNum = i + 2;
            const sn = (row['SN'] ?? row['sn'] ?? '').toString().trim();
            if (!sn) {
                errors.push({ row: rowNum, message: 'SN is required' });
                continue;
            }
            if (snsInFile.has(sn)) {
                errors.push({ row: rowNum, message: `Duplicate SN "${sn}" in file` });
                continue;
            }
            snsInFile.add(sn);
            const model = (row['Model'] ?? row['model'] ?? '').toString().trim();
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
    async bulkImport(rows, userId, installerId) {
        const { valid, errors } = await this.validateRows(rows);
        let successCount = 0;
        if (valid.length > 0) {
            const stationMap = new Map();
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
            const devices = valid.map((v) => this.deviceRepo.create({
                sn: v.sn,
                model: v.model,
                rated_power: v.ratedPower,
                firmware_version: v.firmwareVersion,
                hardware_version: v.hardwareVersion,
                station_id: v.stationName ? (stationMap.get(v.stationName) ?? null) : null,
                user_id: userId,
                installer_id: installerId,
                status: 1,
            }));
            await this.deviceRepo.save(devices);
            successCount = devices.length;
        }
        return {
            success: successCount,
            failed: errors.length,
            errors,
        };
    }
};
exports.ExcelImportService = ExcelImportService;
exports.ExcelImportService = ExcelImportService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __param(1, (0, typeorm_1.InjectRepository)(station_entity_1.Station)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository])
], ExcelImportService);
//# sourceMappingURL=excel-import.service.js.map