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
#include <time.h>

// ===========================================================================
// OVERNIGHT CAFE — ESP32 RFID ATTENDANCE & FIREBASE INTEGRATION
// Firebase Project: appdev-8edd2
// ===========================================================================

// ---- WiFi Configuration ----
const char* WIFI_SSID = "SALT";
const char* WIFI_PASSWORD = "KONEK_kaditoSALT19";

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

// ---- Employee Record & Attendance Structures ----
struct EmployeeMatch {
  bool found = false;
  String fullName = "";
  String email = "";
  String id = "";
};

struct AttendanceStatus {
  bool hasOpenShift = false;
  String attendanceDocId = "";
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

// ---- NTP Time Sync (Philippine Time UTC+8) ----
void setupNtp() {
  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("Syncing NTP Time (Asia/Manila)");
  unsigned long start = millis();
  struct tm timeinfo;
  while (!getLocalTime(&timeinfo) && millis() - start < 10000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nNTP Synced!");
}

String getCurrentTimeString() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) {
    return "00:00 AM";
  }
  char buf[10];
  int hour = timeinfo.tm_hour;
  int minute = timeinfo.tm_min;
  const char* period = (hour < 12) ? "AM" : "PM";
  int hour12 = hour % 12;
  if (hour12 == 0) hour12 = 12;
  sprintf(buf, "%d:%02d %s", hour12, minute, period);
  return String(buf);
}

bool isTimeoutWindow() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) {
    return false;
  }
  // 2:00 AM to 2:30 AM window for Time Out
  return (timeinfo.tm_hour == 2 && timeinfo.tm_min >= 0 && timeinfo.tm_min <= 30);
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
    showScreen("WiFi OK", WiFi.localIP().toString(), "Syncing NTP...");
    setupNtp();
    delay(800);
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
  http.setTimeout(3000);
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
      if (!firstRes["document"].isNull()) {
        JsonObject fields = firstRes["document"]["fields"];
        match.found = true;

        if (!fields["fullName"].isNull()) {
          match.fullName = fields["fullName"]["stringValue"].as<String>();
        }
        if (!fields["email"].isNull()) {
          match.email = fields["email"]["stringValue"].as<String>();
        }
        if (!firstRes["document"]["name"].isNull()) {
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

// ---- Check Employee Open Attendance Status ----
AttendanceStatus getEmployeeAttendanceStatus(const String& employeeName) {
  AttendanceStatus status;
  if (WiFi.status() != WL_CONNECTED || employeeName.length() == 0) return status;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(3000);
  String queryUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents:runQuery";

  http.begin(client, queryUrl);
  http.addHeader("Content-Type", "application/json");

  JsonDocument doc;
  JsonObject structuredQuery = doc["structuredQuery"].to<JsonObject>();

  JsonArray from = structuredQuery["from"].to<JsonArray>();
  JsonObject collection = from.add<JsonObject>();
  collection["collectionId"] = "attendance";

  JsonObject whereObj = structuredQuery["where"].to<JsonObject>();
  JsonObject fieldFilter = whereObj["fieldFilter"].to<JsonObject>();
  fieldFilter["field"]["fieldPath"] = "employeeName";
  fieldFilter["op"] = "EQUAL";
  fieldFilter["value"]["stringValue"] = employeeName;

  String requestBody;
  serializeJson(doc, requestBody);

  int httpCode = http.POST(requestBody);
  String responseBody = http.getString();
  http.end();

  if (httpCode == 200 && responseBody.length() > 0) {
    JsonDocument resDoc;
    DeserializationError err = deserializeJson(resDoc, responseBody);
    if (!err && resDoc.is<JsonArray>() && resDoc.size() > 0) {
      for (JsonObject res : resDoc.as<JsonArray>()) {
        if (!res["document"].isNull()) {
          JsonObject fields = res["document"]["fields"];
          // Has timed in, but timeOut is null (open shift)
          if (!fields["timeIn"].isNull() && fields["timeOut"].isNull()) {
            status.hasOpenShift = true;
            String docPath = res["document"]["name"].as<String>();
            int lastSlash = docPath.lastIndexOf('/');
            if (lastSlash != -1) {
              status.attendanceDocId = docPath.substring(lastSlash + 1);
            }
            break;
          }
        }
      }
    }
  }

  return status;
}

// ---- Check if Employee Already Completed Shift Today ----
bool hasAlreadyTappedToday(const String& employeeName) {
  if (WiFi.status() != WL_CONNECTED || employeeName.length() == 0) return false;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(3000);
  String queryUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents:runQuery";

  http.begin(client, queryUrl);
  http.addHeader("Content-Type", "application/json");

  JsonDocument doc;
  JsonObject structuredQuery = doc["structuredQuery"].to<JsonObject>();

  JsonArray from = structuredQuery["from"].to<JsonArray>();
  JsonObject collection = from.add<JsonObject>();
  collection["collectionId"] = "attendance";

  JsonObject whereObj = structuredQuery["where"].to<JsonObject>();
  JsonObject fieldFilter = whereObj["fieldFilter"].to<JsonObject>();
  fieldFilter["field"]["fieldPath"] = "employeeName";
  fieldFilter["op"] = "EQUAL";
  fieldFilter["value"]["stringValue"] = employeeName;

  String requestBody;
  serializeJson(doc, requestBody);

  int httpCode = http.POST(requestBody);
  String responseBody = http.getString();
  http.end();

  if (httpCode == 200 && responseBody.length() > 0) {
    JsonDocument resDoc;
    DeserializationError err = deserializeJson(resDoc, responseBody);
    if (!err && resDoc.is<JsonArray>() && resDoc.size() > 0) {
      for (JsonObject res : resDoc.as<JsonArray>()) {
        if (!res["document"].isNull()) {
          JsonObject fields = res["document"]["fields"];
          if (!fields["timeIn"].isNull() && fields["timeOut"].isNull() && !isTimeoutWindow()) {
            return true;
          }
        }
      }
    }
  }

  return false;
}

// ---- Firebase Firestore Push: Log RFID Scan Event ----
bool postRfidScanToFirebase(const String& uid, const String& employeeName = "") {
  if (WiFi.status() != WL_CONNECTED) return false;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(3000);
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

  if (!emp.found) {
    postRfidScanToFirebase(uid, "");
    Serial.println("UNREGISTERED CARD.");
    showScreen("Unregistered Card", "Not Linked", "UID: " + uid);
    beepFail();
    return;
  }

  // 2. Check current Philippine time via NTP
  struct tm timeinfo;
  bool timeSynced = getLocalTime(&timeinfo);
  int currentHour = timeSynced ? timeinfo.tm_hour : 19;

  // Check if employee has an open shift (already timed in)
  AttendanceStatus attStatus = getEmployeeAttendanceStatus(emp.fullName);

  if (attStatus.hasOpenShift) {
    // Attempting Time Out before 2:00 AM (02:00)
    if (currentHour < 2) {
      Serial.println("TIME OUT BLOCKED: Before 2:00 AM for " + emp.fullName);
      showScreen(emp.fullName, "Time Out Opens", "at 2:00 AM");
      beepFail();
      return;
    }
  } else {
    // Attempting Time In - check duplicate tap
    if (hasAlreadyTappedToday(emp.fullName)) {
      Serial.println("ALREADY TAPPED TODAY: " + emp.fullName);
      showScreen(emp.fullName, "ALREADY TAPPED", "Already recorded");
      beepFail();
      return;
    }
  }

  // 3. Determine Action: Time In vs Time Out
  bool timeoutMode = (currentHour == 2 && timeinfo.tm_min >= 0 && timeinfo.tm_min <= 30);
  String timeStr = getCurrentTimeString();
  String actionLabel = timeoutMode ? "TIME OUT " + timeStr : "TIME IN " + timeStr;

  // 4. Push Scan to Firebase for real-time app sync & attendance logging
  postRfidScanToFirebase(uid, emp.fullName);

  // 5. Display Success Result on OLED & Play Sound
  Serial.printf("ATTENDANCE SUCCESS! Employee: %s | Action: %s\n", emp.fullName.c_str(), actionLabel.c_str());
  showScreen(emp.fullName, actionLabel, emp.email.length() > 0 ? emp.email : uid);
  beepOk();
}

// ---- Setup: Automatic Initialization on Power Up ----
void setup() {
  Serial.begin(115200);
  Serial.println("\n--- Overnight Cafe RFID Attendance Scanner ---");

  // Initialize OLED
  Wire.begin(OLED_SDA, OLED_SCL);
  oledOk = display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);
  Serial.println(oledOk ? "OLED Display Ready." : "OLED Display not detected.");
  showScreen("Overnight Cafe", "Starting...");

  // Initialize MFRC522 RFID Reader Hardware
  SPI.begin(18, 19, 23, SS_PIN);
  rfid.PCD_Init();
  rfid.PCD_DumpVersionToSerial();

  // Connect to WiFi & Sync NTP Time
  connectWifi();

  showScreen("Overnight Cafe", "TAP CARD", "Ready for Shift");
  Serial.println("System Ready. Continuous loop active.");
}

// ---- Main Non-Blocking Continuous Loop ----
void loop() {
  unsigned long now = millis();

  // Reconnect WiFi in background if disconnected
  if (WiFi.status() != WL_CONNECTED) {
    static unsigned long lastRetry = 0;
    if (now - lastRetry > 15000) {
      lastRetry = now;
      WiFi.reconnect();
    }
  }

  // Non-blocking screen reset timer
  static unsigned long lastScanTime = 0;
  static String lastScannedUid = "";
  static unsigned long screenResetTime = 0;
  static bool screenNeedsReset = false;
  static unsigned long lastPcdInitTime = 0;

  if (screenNeedsReset && now >= screenResetTime) {
    screenNeedsReset = false;
    showScreen("Overnight Cafe", "TAP CARD", "Ready for Shift");
  }

  // Periodic defensive PCD re-init every 10 seconds to prevent MFRC522 freezing
  if (now - lastPcdInitTime > 10000) {
    lastPcdInitTime = now;
    rfid.PCD_Init();
  }

  // Check if a card is present
  if (!rfid.PICC_IsNewCardPresent()) {
    lastScannedUid = ""; // Reset last UID when card is removed so re-tapping works
    return;
  }

  if (!rfid.PICC_ReadCardSerial()) {
    return;
  }

  String uid = readUid();

  // Always halt PICC and stop crypto immediately after reading UID
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();

  // Non-blocking Cooldown check: ignore if same card is tapped within 2 seconds
  if (uid == lastScannedUid && (now - lastScanTime < 2000)) {
    return;
  }

  if (uid.length() > 0) {
    lastScanTime = now;
    lastScannedUid = uid;

    processCardScan(uid);

    // Schedule screen reset 2 seconds later (non-blocking)
    screenResetTime = millis() + 2000;
    screenNeedsReset = true;

    // Hard reset PCD reader state so next card scan is 100% responsive
    rfid.PCD_Init();
  }
}
