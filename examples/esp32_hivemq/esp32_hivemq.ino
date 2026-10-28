// River Flow Guardian - ESP32 -> HiveMQ Cloud MQTT
// Arduino IDE libraries: PubSubClient, ArduinoJson
// Credentials are placeholders. Jangan commit credential production.

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

const char* WIFI_SSID = "Mine";
const char* WIFI_PASSWORD = "war54321";
const char* MQTT_HOST = "YOUR_CLUSTER.s1.eu.hivemq.cloud";
const uint16_t MQTT_PORT = 8883;
const char* MQTT_USERNAME = "YOUR_HIVEMQ_USERNAME";
const char* MQTT_PASSWORD = "YOUR_HIVEMQ_PASSWORD";

const char* STATION_ID = "00000000-0000-0000-0000-000000000001";
const char* DEVICE_ID = "00000000-0000-0000-0000-000000000004";
const char* MQTT_TOPIC = "river-flow/v1/telemetry";

WiFiClientSecure tlsClient;
PubSubClient mqtt(tlsClient);
unsigned long lastPublish = 0;

void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) delay(500);
}

void connectMqtt() {
  while (!mqtt.connected()) {
    String clientId = String("rfg-esp32-") + DEVICE_ID;
    if (mqtt.connect(clientId.c_str(), MQTT_USERNAME, MQTT_PASSWORD,
                     (String("river-flow/v1/status/") + DEVICE_ID).c_str(), 1, true, "offline")) {
      String onlineTopic = String("river-flow/v1/status/") + DEVICE_ID;
      mqtt.publish(onlineTopic.c_str(), "online", true);
    } else {
      delay(3000);
    }
  }
}

void publishTelemetry() {
  StaticJsonDocument<512> doc;
  doc["station_id"] = STATION_ID;
  doc["device_id"] = DEVICE_ID;
  doc["source_timestamp"] = millis(); // Ganti dengan Unix timestamp dari NTP/RTC
  JsonArray values = doc.createNestedArray("values");

  JsonObject water = values.createNestedObject();
  water["tag_id"] = "HYDRO.WATER_LEVEL";
  water["value"] = 1.25; // Ganti pembacaan sensor
  water["quality"] = "good";

  JsonObject flow = values.createNestedObject();
  flow["tag_id"] = "HYDRO.FLOW_RATE";
  flow["value"] = 8.40; // Ganti pembacaan sensor
  flow["quality"] = "good";

  char payload[512];
  serializeJson(doc, payload, sizeof(payload));
  mqtt.publish(MQTT_TOPIC, payload);
}

void setup() {
  Serial.begin(115200);
  connectWiFi();
  tlsClient.setInsecure(); // Produksi: gunakan CA certificate HiveMQ, bukan setInsecure().
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  if (!mqtt.connected()) connectMqtt();
  mqtt.loop();
  if (millis() - lastPublish >= 5000) {
    lastPublish = millis();
    publishTelemetry();
  }
}