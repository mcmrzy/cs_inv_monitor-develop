"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
require("reflect-metadata");
const typeorm_1 = require("typeorm");
const bcrypt = require("bcryptjs");
const user_entity_1 = require("./entities/user.entity");
async function seed() {
    const ds = new typeorm_1.DataSource({
        type: 'postgres',
        host: process.env.DB_HOST || 'localhost',
        port: parseInt(process.env.DB_PORT || '5432', 10),
        username: process.env.DB_USER || 'postgres',
        password: process.env.DB_PASS || 'cs_inv_admin_2026_test',
        database: process.env.DB_NAME || 'inv_mqtt',
        entities: [user_entity_1.User],
        synchronize: false,
        logging: false,
    });
    await ds.initialize();
    const userRepo = ds.getRepository(user_entity_1.User);
    const defaultUsers = [
        {
            phone: '13800000001',
            email: 'superadmin@inv-mqtt.com',
            nickname: '超级管理员',
            role: 0,
            status: 1,
            password: 'admin123',
        },
        {
            phone: '13800000002',
            email: 'agent@inv-mqtt.com',
            nickname: '华东代理商',
            role: 1,
            status: 1,
            password: 'agent123',
            parent_id: null,
        },
        {
            phone: '13800000003',
            email: 'installer@inv-mqtt.com',
            nickname: '上海安装商',
            role: 2,
            status: 1,
            password: 'installer123',
            parent_id: null,
        },
        {
            phone: '13800000004',
            email: 'user@inv-mqtt.com',
            nickname: '测试用户',
            role: 3,
            status: 1,
            password: 'user123',
            parent_id: null,
        },
    ];
    let superAdminId = null;
    let agentId = null;
    let installerId = null;
    for (const u of defaultUsers) {
        const exists = await userRepo.findOne({
            where: { phone: u.phone },
        });
        if (exists) {
            console.log(`User ${u.nickname} (${u.phone}) already exists, skipping.`);
            if (u.role === 0)
                superAdminId = exists.id;
            if (u.role === 1)
                agentId = exists.id;
            if (u.role === 2)
                installerId = exists.id;
            continue;
        }
        const hash = await bcrypt.hash(u.password, 12);
        if (u.role === 1)
            u.parent_id = superAdminId;
        if (u.role === 2)
            u.parent_id = agentId;
        if (u.role === 3)
            u.parent_id = installerId;
        const saved = await userRepo.save(userRepo.create({
            phone: u.phone,
            email: u.email,
            password_hash: hash,
            nickname: u.nickname,
            role: u.role,
            parent_id: u.parent_id ?? null,
            status: u.status,
        }));
        if (u.role === 0)
            superAdminId = saved.id;
        if (u.role === 1)
            agentId = saved.id;
        if (u.role === 2)
            installerId = saved.id;
        console.log(`Created user: ${u.nickname} (${u.phone}) password: ${u.password}`);
    }
    console.log('\n=== 默认账号 ===');
    console.log('超级管理员: 13800000001 / admin123');
    console.log('代理商:     13800000002 / agent123');
    console.log('安装商:     13800000003 / installer123');
    console.log('最终用户:   13800000004 / user123');
    console.log('(也可使用邮箱登录)\n');
    await ds.destroy();
}
seed().catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
});
//# sourceMappingURL=seed.js.map