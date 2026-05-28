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
var GeoLocationService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.GeoLocationService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const schedule_1 = require("@nestjs/schedule");
const device_entity_1 = require("../../entities/device.entity");
const station_entity_1 = require("../../entities/station.entity");
let GeoLocationService = GeoLocationService_1 = class GeoLocationService {
    constructor(deviceRepo, stationRepo) {
        this.deviceRepo = deviceRepo;
        this.stationRepo = stationRepo;
        this.logger = new common_1.Logger(GeoLocationService_1.name);
        this.processedIPs = new Map();
    }
    async autoSyncStationCoords() {
        this.logger.log('Starting auto station coordinate sync...');
        const devices = await this.deviceRepo
            .createQueryBuilder('d')
            .select(['d.sn', 'd.ip_address', 'd.station_id'])
            .where('d.ip_address IS NOT NULL')
            .andWhere("d.ip_address != ''")
            .andWhere('d.station_id IS NOT NULL')
            .getRawMany();
        for (const d of devices) {
            const ip = d.d_ip_address;
            const stationId = d.d_station_id;
            if (!ip || !stationId)
                continue;
            if (this.processedIPs.has(ip)) {
                const coords = this.processedIPs.get(ip);
                if (coords) {
                    await this.updateStationCoords(stationId, coords.lat, coords.lng);
                }
                continue;
            }
            try {
                const coords = await this.geolocateIP(ip);
                if (coords) {
                    this.processedIPs.set(ip, coords);
                    await this.updateStationCoords(stationId, coords.lat, coords.lng);
                    this.logger.log(`Updated station ${stationId} coords from IP ${ip}`);
                }
                else {
                    this.processedIPs.set(ip, null);
                }
            }
            catch {
                this.logger.warn(`Failed to geolocate IP: ${ip}`);
            }
        }
    }
    async updateStationCoords(stationId, lat, lng) {
        await this.stationRepo
            .createQueryBuilder()
            .update(station_entity_1.Station)
            .set({ latitude: lat, longitude: lng, updated_at: new Date() })
            .where('id = :id', { id: stationId })
            .andWhere('(latitude = 0 OR latitude IS NULL)')
            .execute();
    }
    async geolocateIP(ip) {
        if (!ip || ip === '127.0.0.1' || ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.16.')) {
            return null;
        }
        const apis = [
            async () => this.tryIpApiCom(ip),
            async () => this.tryPConline(ip),
            async () => this.tryBaiduIp(ip),
        ];
        for (const api of apis) {
            try {
                const result = await api();
                if (result)
                    return result;
            }
            catch {
                continue;
            }
        }
        return null;
    }
    async tryIpApiCom(ip) {
        try {
            const resp = await fetch(`https://ipapi.com/ip_api.php?ip=${ip}`, { signal: AbortSignal.timeout(5000) });
            const json = await resp.json();
            if (json.latitude && json.longitude) {
                const [gcjLng, gcjLat] = wgs84ToGcj02(json.longitude, json.latitude);
                return { lat: gcjLat, lng: gcjLng };
            }
        }
        catch {
            return null;
        }
        return null;
    }
    async tryPConline(ip) {
        return new Promise((resolve) => {
            const http = require('http');
            http.get(`http://whois.pconline.com.cn/ipJson.jsp?ip=${ip}&json=true`, (resp) => {
                let data = '';
                resp.on('data', (chunk) => { data += chunk; });
                resp.on('end', () => {
                    try {
                        const json = JSON.parse(data.toString().replace(/^\uFEFF/, ''));
                        const city = json.pro + json.city;
                        if (city) {
                            const coords = CITY_COORDS[city] || CITY_COORDS[json.pro];
                            resolve(coords || null);
                        }
                        else {
                            resolve(null);
                        }
                    }
                    catch {
                        resolve(null);
                    }
                });
            }).on('error', () => resolve(null))
                .setTimeout(5000, function () { this.destroy(); resolve(null); });
        });
    }
    async tryBaiduIp(ip) {
        const resp = await fetch(`http://opendata.baidu.com/api.php?query=${ip}&co=&resource_id=6006&oe=utf8`, {
            signal: AbortSignal.timeout(5000),
        });
        const json = await resp.json();
        const location = json?.data?.[0]?.location;
        if (location) {
            const province = location.split('省')[0].trim() + '省';
            const city = location.split('省')[1]?.split(' ')[0]?.trim();
            const key = city || province;
            return CITY_COORDS[key] || null;
        }
        return null;
    }
    async tryAmapCity(ip) {
        try {
            const resp = await fetch(`https://restapi.amap.com/v3/ip?ip=${ip}&output=json&key=`, {
                signal: AbortSignal.timeout(5000),
            });
            const json = await resp.json();
            if (json?.rectangle) {
                const parts = json.rectangle.split(';')[0].split(',');
                if (parts.length === 2) {
                    const lng = parseFloat(parts[0]);
                    const lat = parseFloat(parts[1]);
                    if (lat && lng)
                        return { lat, lng };
                }
            }
        }
        catch {
            return null;
        }
        return null;
    }
};
exports.GeoLocationService = GeoLocationService;
__decorate([
    (0, schedule_1.Cron)('0 */5 * * * *'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], GeoLocationService.prototype, "autoSyncStationCoords", null);
exports.GeoLocationService = GeoLocationService = GeoLocationService_1 = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __param(1, (0, typeorm_1.InjectRepository)(station_entity_1.Station)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository])
], GeoLocationService);
const CITY_COORDS = {
    '广东省广州市': { lat: 23.1292, lng: 113.2644 },
    '广东省深圳市': { lat: 22.5431, lng: 114.0579 },
    '广东省东莞市': { lat: 23.0207, lng: 113.7518 },
    '广东省佛山市': { lat: 23.0218, lng: 113.1216 },
    '广东省珠海市': { lat: 22.2707, lng: 113.5767 },
    '广东省中山市': { lat: 22.5167, lng: 113.3833 },
    '广东省惠州市': { lat: 23.1118, lng: 114.4156 },
    '湖南省长沙市': { lat: 28.2282, lng: 112.9388 },
    '湖南省株洲市': { lat: 27.8277, lng: 113.1340 },
    '湖南省湘潭市': { lat: 27.8298, lng: 112.9440 },
    '湖南省衡阳市': { lat: 26.8934, lng: 112.5720 },
    '湖南省邵阳市': { lat: 27.2389, lng: 111.4677 },
    '湖南省岳阳市': { lat: 29.3573, lng: 113.1289 },
    '湖南省常德市': { lat: 29.0316, lng: 111.6985 },
    '湖南省张家界': { lat: 29.1167, lng: 110.4783 },
    '湖南省益阳市': { lat: 28.5539, lng: 112.3551 },
    '湖南省郴州市': { lat: 25.7706, lng: 113.0146 },
    '湖南省永州市': { lat: 26.4203, lng: 111.6141 },
    '湖南省怀化市': { lat: 27.5698, lng: 109.9992 },
    '湖南省娄底市': { lat: 27.6972, lng: 111.9948 },
    '北京市': { lat: 39.9042, lng: 116.4074 },
    '上海市': { lat: 31.2304, lng: 121.4737 },
    '天津市': { lat: 39.0842, lng: 117.2009 },
    '重庆市': { lat: 29.4316, lng: 106.9123 },
    '浙江省杭州市': { lat: 30.2741, lng: 120.1551 },
    '浙江省宁波市': { lat: 29.8683, lng: 121.5440 },
    '浙江省温州市': { lat: 28.0226, lng: 120.6994 },
    '江苏省南京市': { lat: 32.0603, lng: 118.7969 },
    '江苏省苏州市': { lat: 31.2990, lng: 120.5853 },
    '江苏省无锡市': { lat: 31.4910, lng: 120.3124 },
    '江苏省常州市': { lat: 31.8108, lng: 119.9740 },
    '湖北省武汉市': { lat: 30.5928, lng: 114.3055 },
    '湖北省宜昌市': { lat: 30.6917, lng: 111.2860 },
    '四川省成都市': { lat: 30.5728, lng: 104.0668 },
    '四川省绵阳市': { lat: 31.4675, lng: 104.6789 },
    '山东省济南市': { lat: 36.6512, lng: 117.1201 },
    '山东省青岛市': { lat: 36.0671, lng: 120.3826 },
    '福建省福州市': { lat: 26.0745, lng: 119.2965 },
    '福建省厦门市': { lat: 24.4798, lng: 118.0894 },
    '福建省泉州市': { lat: 24.8744, lng: 118.6757 },
    '河南省郑州市': { lat: 34.7466, lng: 113.6254 },
    '河南省洛阳市': { lat: 34.6181, lng: 112.4539 },
    '河北省石家庄': { lat: 38.0428, lng: 114.5149 },
    '辽宁省沈阳市': { lat: 41.8057, lng: 123.4315 },
    '辽宁省大连市': { lat: 38.9140, lng: 121.6147 },
    '陕西省西安市': { lat: 34.3416, lng: 108.9398 },
    '安徽省合肥市': { lat: 31.8206, lng: 117.2272 },
    '江西省南昌市': { lat: 28.6820, lng: 115.8579 },
    '云南省昆明市': { lat: 25.0389, lng: 102.7183 },
    '贵州省贵阳市': { lat: 26.6470, lng: 106.6302 },
    '广西南宁市': { lat: 22.8175, lng: 108.3666 },
    '山西省太原市': { lat: 37.8706, lng: 112.5489 },
    '吉林省长春市': { lat: 43.8160, lng: 125.3236 },
    '黑龙江省': { lat: 45.8038, lng: 126.5350 },
    '黑龙江省哈尔滨': { lat: 45.8038, lng: 126.5350 },
    '内蒙古': { lat: 40.8175, lng: 111.7656 },
    '海南省海口市': { lat: 20.0440, lng: 110.1999 },
    '海南省三亚市': { lat: 18.2528, lng: 109.5120 },
    '甘肃省兰州市': { lat: 36.0614, lng: 103.8343 },
    '青海省西宁市': { lat: 36.6171, lng: 101.7785 },
    '宁夏银川市': { lat: 38.4872, lng: 106.2309 },
    '新疆': { lat: 43.7930, lng: 87.6278 },
    '西藏': { lat: 29.6470, lng: 91.1172 },
    '广东省': { lat: 23.1317, lng: 113.2663 },
    '湖南省': { lat: 28.1126, lng: 113.0000 },
    '浙江省': { lat: 30.2741, lng: 120.1551 },
    '江苏省': { lat: 32.0603, lng: 118.7969 },
    '湖北省': { lat: 30.5928, lng: 114.3055 },
    '四川省': { lat: 30.5728, lng: 104.0668 },
    '山东省': { lat: 36.6512, lng: 117.1201 },
    '福建省': { lat: 26.0745, lng: 119.2965 },
    '河南省': { lat: 34.7466, lng: 113.6254 },
    '河北省': { lat: 38.0428, lng: 114.5149 },
    '辽宁省': { lat: 41.8057, lng: 123.4315 },
    '陕西省': { lat: 34.3416, lng: 108.9398 },
    '安徽省': { lat: 31.8206, lng: 117.2272 },
    '江西省': { lat: 28.6820, lng: 115.8579 },
    '云南省': { lat: 25.0389, lng: 102.7183 },
    '贵州省': { lat: 26.6470, lng: 106.6302 },
    '广西': { lat: 22.8175, lng: 108.3666 },
    '山西省': { lat: 37.8706, lng: 112.5489 },
    '吉林省': { lat: 43.8160, lng: 125.3236 },
    '海南省': { lat: 20.0440, lng: 110.1999 },
    '甘肃省': { lat: 36.0614, lng: 103.8343 },
    '青海省': { lat: 36.6171, lng: 101.7785 },
    '宁夏': { lat: 38.4872, lng: 106.2309 },
};
function outOfChina(lon, lat) {
    return lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;
}
function transformLat(x, y) {
    let ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
    ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
    ret += (20.0 * Math.sin(y * Math.PI) + 40.0 * Math.sin(y / 3.0 * Math.PI)) * 2.0 / 3.0;
    ret += (160.0 * Math.sin(y / 12.0 * Math.PI) + 320.0 * Math.sin(y * Math.PI / 30.0)) * 2.0 / 3.0;
    return ret;
}
function transformLon(x, y) {
    let ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
    ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
    ret += (20.0 * Math.sin(x * Math.PI) + 40.0 * Math.sin(x / 3.0 * Math.PI)) * 2.0 / 3.0;
    ret += (150.0 * Math.sin(x / 12.0 * Math.PI) + 300.0 * Math.sin(x / 30.0 * Math.PI)) * 2.0 / 3.0;
    return ret;
}
function wgs84ToGcj02(lon, lat) {
    if (outOfChina(lon, lat)) {
        return [lon, lat];
    }
    const a = 6378245.0;
    const ee = 0.00669342162296594323;
    let dLat = transformLat(lon - 105.0, lat - 35.0);
    let dLon = transformLon(lon - 105.0, lat - 35.0);
    const radLat = lat * Math.PI / 180.0;
    let magic = Math.sin(radLat);
    magic = 1 - ee * magic * magic;
    const sqrtMagic = Math.sqrt(magic);
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * Math.PI);
    dLon = (dLon * 180.0) / (a / sqrtMagic * Math.cos(radLat) * Math.PI);
    return [lon + dLon, lat + dLat];
}
//# sourceMappingURL=geo-location.service.js.map