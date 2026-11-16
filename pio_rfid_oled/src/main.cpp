#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <MFRC522.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ArduinoJson.h>

// ===========================================================================
// OVERNIGHT CAFE — ESP32 RFID ATTENDANCE & FIREBASE INTEGRATION
// Firebase Project: appdev-8edd2
// ===========================================================================

// ---- WiFi Configuration ----
const char* WIFI_SSID = "paul";
const char* WIFI_PASSWORD = "12345678";

// ---- Firebase Configuration ----
const char* FIREBASE_PROJECT_ID = "appdev-8edd2";

// ---- Hardware Pins ----
#define SS_PIN 5
#define RST_PIN 21
#define BUZZER_PIN 4
#define OLED_SDA 16  // RX2
#define OLED_SCL 17  // TX2
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
#define OLED_ADDR 0x3C

MFRC522 rfid(SS_PIN, RST_PIN);
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
bool oledOk = false;

// ---- Employee Record Structure ----
struct EmployeeMatch {
  bool found = false;
  String fullName = "";
  String email = "";
  String id = "";
};

// ---- Passive Speaker/Buzzer Tones ----
void beep(int freq, int ms) {
  tone(BUZZER_PIN, freq, ms);
  delay(ms);
  noTone(BUZZER_PIN);
}

void beepOk() {
  beep(2600, 150);
  delay(80);
  beep(2600, 150);
}

void beepLink() {
  beep(2000, 100);
  delay(60);
  beep(2000, 100);
  delay(60);
  beep(2600, 250);
}

void beepFail() {
  beep(300, 500);
}

// ---- OLED Display Helper ----
void showScreen(const String& l1, const String& l2 = "", const String& l3 = "") {
  if (!oledOk) return;

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println(l1);

  if (l2.length() > 0) {
    display.setTextSize(2);
    display.setCursor(0, 18);
    display.println(l2);
  }

  display.setTextSize(1);
  if (l3.length() > 0) {
    display.setCursor(0, 52);
    display.println(l3);
  }

  display.display();
}

// ---- WiFi Connection Handler ----
void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  showScreen("WiFi Connection", "Connecting");
  Serial.print("Connecting to WiFi: ");
  Serial.println(WIFI_SSID);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("\nWiFi Connected! IP: ");
    Serial.println(WiFi.localIP());
    showScreen("WiFi OK", WiFi.localIP().toString(), "Overnight Cafe");
    delay(1000);
  } else {
    Serial.println("\nWiFi connection failed. Retrying in background...");
    showScreen("WiFi FAILED", "OFFLINE", "Retrying...");
    beepFail();
    delay(1000);
  }
}

// ---- RFID Hex UID Converter ----
String readUid() {
  String uid = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] < 0x10) uid += "0";
    uid += String(rfid.uid.uidByte[i], HEX);
  }
  uid.toUpperCase();
  return uid;
}

// ---- Firebase Firestore Query: Match RFID Card UID with Employee Email ----
EmployeeMatch findEmployeeByRfid(const String& uid) {
  EmployeeMatch match;
  if (WiFi.status() != WL_CONNECTED) return match;

  WiFiClientSecure client;
  client.setInsecure(); // SSL Connection for HTTPS Firestore API

  HTTPClient http;
  String queryUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents:runQuery";

  http.begin(client, queryUrl);
  http.addHeader("Content-Type", "application/json");

  // Construct Firestore runQuery JSON
  JsonDocument doc;
  JsonObject structuredQuery = doc["structuredQuery"].to<JsonObject>();

  JsonArray from = structuredQuery["from"].to<JsonArray>();
  JsonObject collection = from.add<JsonObject>();
  collection["collectionId"] = "users";

  JsonObject whereObj = structuredQuery["where"].to<JsonObject>();
  JsonObject fieldFilter = whereObj["fieldFilter"].to<JsonObject>();
  fieldFilter["field"]["fieldPath"] = "rfidCardId";
  fieldFilter["op"] = "EQUAL";
  fieldFilter["value"]["stringValue"] = uid;

  String requestBody;
  serializeJson(doc, requestBody);

  int httpCode = http.POST(requestBody);
  String responseBody = http.getString();
  http.end();

  Serial.printf("Firestore query HTTP %d\n", httpCode);

  if (httpCode == 200 && responseBody.length() > 0) {
    JsonDocument resDoc;
    DeserializationError err = deserializeJson(resDoc, responseBody);
    if (!err && resDoc.is<JsonArray>() && resDoc.size() > 0) {
      JsonObject firstRes = resDoc[0];
      if (firstRes.containsKey("document")) {
        JsonObject fields = firstRes["document"]["fields"];
        match.found = true;

        if (fields.containsKey("fullName")) {
          match.fullName = fields["fullName"]["stringValue"].as<String>();
        }
        if (fields.containsKey("email")) {
          match.email = fields["email"]["stringValue"].as<String>();
        }
        if (firstRes["document"].containsKey("name")) {
          String docPath = firstRes["document"]["name"].as<String>();
          int lastSlash = docPath.lastIndexOf('/');
          if (lastSlash != -1) {
            match.id = docPath.substring(lastSlash + 1);
          }
        }
      }
    }
  }

  return match;
}

// ---- Firebase Firestore Push: Log RFID Scan Event ----
bool postRfidScanToFirebase(const String& uid, const String& employeeName = "") {
  if (WiFi.status() != WL_CONNECTED) return false;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  String postUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents/rfidScans";

  http.begin(client, postUrl);
  http.addHeader("Content-Type", "application/json");

  JsonDocument doc;
  JsonObject fields = doc["fields"].to<JsonObject>();
  fields["rfidTag"]["stringValue"] = uid;
  if (employeeName.length() > 0) {
    fields["employeeName"]["stringValue"] = employeeName;
  }

  String requestBody;
  serializeJson(doc, requestBody);

  int httpCode = http.POST(requestBody);
  http.end();

  Serial.printf("Firestore rfidScans push HTTP %d\n", httpCode);
  return (httpCode == 200 || httpCode == 201);
}

// ---- Handle Scanned RFID Card Event ----
void processCardScan(const String& uid) {
  showScreen("Checking Card...", uid);
  Serial.println("Processing Card UID: " + uid);

  // 1. Query Firestore for Employee matching rfidCardId
  EmployeeMatch emp = findEmployeeByRfid(uid);

  // 2. Push Scan to Firebase for real-time app sync & attendance logging
  postRfidScanToFirebase(uid, emp.fullName);

  // 3. Display Result on OLED & Play Sound
  if (emp.found) {
    Serial.printf("MATCH FOUND! Employee: %s | Email: %s\n", emp.fullName.c_str(), emp.email.c_str());
    showScreen(emp.fullName, "ATTENDANCE", emp.email.length() > 0 ? emp.email : uid);
    beepOk();
  } else {
    Serial.println("UNREGISTERED CARD. Card UID posted to rfidScans for admin linking.");
    showScreen("Unregistered Card", "Not Linked", "UID: " + uid);
    beepFail();
  }
}

// ---- Setup ----
void setup() {
  Serial.begin(115200);
  Serial.println("\n--- Overnight Cafe RFID Attendance Scanner ---");

  // Initialize OLED
  Wire.begin(OLED_SDA, OLED_SCL);
  oledOk = display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);
  Serial.println(oledOk ? "OLED Display Ready." : "OLED Display not detected.");
  showScreen("Overnight Cafe", "Starting...");

  // Initialize MFRC522 RFID Reader
  SPI.begin(18, 19, 23, SS_PIN);
  rfid.PCD_Init();
  rfid.PCD_DumpVersionToSerial();

  // Connect to WiFi
  connectWifi();

  showScreen("Overnight Cafe", "TAP CARD", "Ready for Shift");
  Serial.println("System Ready. Please tap your RFID card.");
}

// ---- Main Loop ----
void loop() {
  // Reconnect WiFi if disconnected
  if (WiFi.status() != WL_CONNECTED) {
    static unsigned long lastRetry = 0;
    if (millis() - lastRetry > 15000) {
      lastRetry = millis();
      WiFi.reconnect();
    }
  }

  // Look for new RFID card tap
  if (!rfid.PICC_IsNewCardPresent()) return;
  if (!rfid.PICC_ReadCardSerial()) return;

  String uid = readUid();
  processCardScan(uid);

  // Halt PICC & Stop Crypto
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();

  delay(3000);
  showScreen("Overnight Cafe", "TAP CARD", "Ready for Shift");
}
