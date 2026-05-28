import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { jwtConfig } from '../../config/jwt.config';
import { EventsGateway } from './websocket.gateway';

@Module({
  imports: [
    JwtModule.register({
      secret: jwtConfig.secret,
      signOptions: { expiresIn: jwtConfig.accessTokenExpires },
    }),
  ],
  providers: [EventsGateway],
  exports: [EventsGateway],
})
export class WebSocketModule {}
