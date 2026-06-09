ALTER TABLE device_telemetry DROP CONSTRAINT "PK_5f9bf90c963405eac930d5733ed";
ALTER TABLE device_telemetry ADD PRIMARY KEY (time, id);
