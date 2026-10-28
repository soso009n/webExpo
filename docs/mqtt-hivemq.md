# ESP32 dan HiveMQ Cloud

Contoh firmware tersedia di `examples/esp32_hivemq/esp32_hivemq.ino`.

## Setup HiveMQ

1. Buat cluster HiveMQ Cloud.
2. Buat username/password khusus device.
3. Isi `MQTT_HOST`, `MQTT_USERNAME`, dan `MQTT_PASSWORD` pada firmware.
4. Gunakan port TLS `8883`.
5. Jangan memasukkan kredensial HiveMQ ke frontend React atau repository.

## Format telemetry

Firmware publish ke:

```text
river-flow/v1/telemetry
```

Payload:

```json
{
  "station_id": "station-uuid",
  "device_id": "device-uuid",
  "source_timestamp": 1710000000,
  "values": [
    {"tag_id": "HYDRO.WATER_LEVEL", "value": 1.25, "quality": "good"}
  ]
}
```

## Penting: MQTT tidak langsung masuk ke Supabase

Diperlukan bridge/consumer backend yang subscribe topic HiveMQ, memvalidasi
`station_id`, `device_id`, dan `tag_id`, lalu melakukan insert ke tabel
`public.measurements`. Jangan expose `service_role` key di ESP32.

Untuk produksi, ganti `tlsClient.setInsecure()` dengan CA certificate HiveMQ
Cloud dan gunakan NTP/RTC untuk `source_timestamp`.