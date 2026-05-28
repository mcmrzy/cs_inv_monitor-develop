import { Repository } from 'typeorm';
import { Station } from '../../entities/station.entity';
import { Role } from '../../common/enums/role.enum';
interface User {
    id: number;
    role: Role;
}
export declare class StationService {
    private stationRepo;
    constructor(stationRepo: Repository<Station>);
    findAll(user: User): Promise<Station[]>;
    assignUser(stationId: number, userId: number): Promise<{
        success: boolean;
    }>;
    update(stationId: number, data: Partial<Station>): Promise<{
        success: boolean;
    }>;
}
export {};
