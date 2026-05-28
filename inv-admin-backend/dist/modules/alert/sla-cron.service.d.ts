import { SlaEngineService } from './sla-engine.service';
export declare class SlaCronService {
    private readonly slaEngineService;
    private readonly logger;
    constructor(slaEngineService: SlaEngineService);
    handleSlaCheck(): Promise<void>;
}
