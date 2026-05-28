import { StationService } from './station.service';
import { Role } from '../../common/enums/role.enum';
export declare class StationController {
    private readonly stationService;
    constructor(stationService: StationService);
    findAll(user: {
        id: number;
        role: Role;
    }): Promise<import("../../entities/station.entity").Station[]>;
    assignUser(id: number, body: {
        user_id: number;
    }): Promise<{
        success: boolean;
    }>;
    update(id: number, body: any): Promise<{
        success: boolean;
    }>;
}
