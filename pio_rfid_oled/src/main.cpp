#include <Arduino.h>
#include <esp_system.h>
#include <Wire.h>
#include <SPI.h>
#include <MFRC522.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <time.h>

// ===========================================================================
// OVERNIGHT CAFE — ESP32 RFID ATTENDANCE & FIREBASE INTEGRATION
// Firebase Project: appdev-8edd2
// Single Unified Collection: 'attendance'
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

// Buzzer test switch: 0 = silent, 1 = buzzer enabled.
#define BUZZER_ENABLED 0

// SPI pins (SCK, MISO, MOSI)
#define SPI_SCK 18
#define SPI_MISO 19
#define SPI_MOSI 23

// ---- Attendance Schedule (Philippine Time, minutes since midnight) ----
// Shift runs overnight: 6:30 PM -> 2:30 AM (next calendar day).
const int TIME_IN_OPEN_MIN    = 18 * 60 + 30;  // 6:30 PM  - Time In opens
const int PRESENT_UNTIL_MIN   = 18 * 60 + 40;  // 6:40 PM  - last minute counted as "Present"
const int TIME_OUT_OPEN_MIN   = 2 * 60;        // 2:00 AM  - Time Out opens
const int TIME_OUT_CLOSE_MIN  = 2 * 60 + 30;   // 2:30 AM  - last minute Time Out is accepted

MFRC522 rfid(SS_PIN, RST_PIN);
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
bool oledOk = false;

// Persistent per-employee attendance state (survives reboot / power loss)
Preferences prefs;

// ---- Runtime State ----
bool ntpSynced = false;       // true once NTP time is valid
bool readerOk = true;         // false while the MFRC522 is not responding
int readerFailStreak = 0;     // consecutive failed recovery attempts
byte lastVersionReg = 0;      // last VersionReg value read (0x00/0xFF = no answer)

// ---- Employee Record & Attendance Structures ----
struct EmployeeMatch {
    bool queryOk = false;   // false = network/server/parse error
    int httpCode = 0;
    bool found = false;
    String fullName = "";
    String email = "";
    String id = "";
};

struct AttendanceStatus {
    bool queryOk = false;
    bool hasOpenShift = false;        // timeIn set, timeOut empty
    bool completedThisShift = false;  // timeIn + timeOut already recorded for the current shift
    String attendanceDocId = "";
};

struct QueryResult {
    bool ok = false;
    int httpCode = 0;
    String body = "";
};

// Per-employee shift record, keyed by RFID UID and tied to the registered email.
// This is only a local mirror. Firebase is always the source of truth.
struct ShiftRecord {
    bool timedIn = false;     // true = open shift (Time In done, Time Out pending)
    String shiftDate = "";    // empty = no record
    String email = "";
};

// ---- Passive Speaker/Buzzer Tones ----
void beep(int freq, int ms) {
#if BUZZER_ENABLED
  tone(BUZZER_PIN, freq, ms);
  delay(ms);
  noTone(BUZZER_PIN);
#else
  (void)freq;
  delay(ms);
#endif
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
    display.setTextSize(l2.length() > 10 ? 1 : 2);
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

// Show an error on the OLED and play the fail tone
void showError(const String& l1, const String& l2, const String& l3 = "") {
  Serial.println("ERROR: " + l1 + " | " + l2 + " | " + l3);
  showScreen(l1, l2, l3);
  beepFail();
}

void showReadyScreen() {
  showScreen("Overnight Cafe", "TAP CARD", "Ready for Shift");
}

// ---- NTP Time Sync (Philippine Time UTC+8) ----
bool setupNtp() {
  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("Syncing NTP Time (Asia/Manila)");
  unsigned long start = millis();
  struct tm timeinfo;
  bool synced = false;
  while (millis() - start < 10000) {
    if (getLocalTime(&timeinfo, 0)) {
      synced = true;
      break;
    }
    delay(500);
    Serial.print(".");
  }
  Serial.println(synced ? "\nNTP Synced!" : "\nNTP sync FAILED (will retry in background).");
  return synced;
}

String getCurrentTimeString() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo, 0)) {
    return "--:-- --";
  }
  char buf[10];
  int hour = timeinfo.tm_hour;
  int minute = timeinfo.tm_min;
  const char* period = (hour < 12) ? "AM" : "PM";
  int hour12 = hour % 12;
  if (hour12 == 0) hour12 = 12;
  snprintf(buf, sizeof(buf), "%d:%02d %s", hour12, minute, period);
  return String(buf);
}

bool isTimeoutWindow() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo, 0)) {
    return false;
  }
  // 2:00 AM to 2:30 AM window for Time Out
  int minutes = timeinfo.tm_hour * 60 + timeinfo.tm_min;
  return (minutes >= TIME_OUT_OPEN_MIN && minutes <= TIME_OUT_CLOSE_MIN);
}

// ---- Shift Date Helper ----
String currentShiftDate(int minutesOfDay) {
  time_t nowT = time(nullptr);
  if (minutesOfDay < TIME_IN_OPEN_MIN) nowT -= 86400;
  struct tm t;
  localtime_r(&nowT, &t);
  char buf[9];
  snprintf(buf, sizeof(buf), "%04d%02d%02d", t.tm_year + 1900, t.tm_mon + 1, t.tm_mday);
  return String(buf);
}

// Derive the shift date (YYYYMMDD) from a stored ISO timestamp such as
// 2026-11-16T19:05:00.000Z (stored as Philippine local time).
// Returns "" if it cannot be parsed.
String shiftDateFromIso(const String& iso) {
  if (iso.length() < 16) return "";
  int y  = iso.substring(0, 4).toInt();
  int mo = iso.substring(5, 7).toInt();
  int d  = iso.substring(8, 10).toInt();
  int h  = iso.substring(11, 13).toInt();
  int mi = iso.substring(14, 16).toInt();
  if (y < 2000 || mo < 1 || d < 1) return "";

  struct tm t = {};
  t.tm_year = y - 1900;
  t.tm_mon = mo - 1;
  t.tm_mday = d;
  t.tm_hour = 12;              // noon avoids DST edge cases when normalizing
  t.tm_isdst = -1;
  if (h * 60 + mi < TIME_IN_OPEN_MIN) t.tm_mday -= 1;  // before 6:30 PM belongs to the previous shift
  mktime(&t);                  // normalizes the date

  char buf[9];
  snprintf(buf, sizeof(buf), "%04d%02d%02d", t.tm_year + 1900, t.tm_mon + 1, t.tm_mday);
  return String(buf);
}

// ---- Per-Employee Attendance State (stored in flash by RFID UID) ----
String prefKeyForUid(const String& uid) {
  return uid.substring(0, 15);  // NVS keys are limited to 15 chars
}

ShiftRecord loadShiftRecord(const String& uid) {
  ShiftRecord rec;
  String raw = prefs.getString(prefKeyForUid(uid).c_str(), "");
  if (raw.length() < 3) return rec;
  int p1 = raw.indexOf('|');
  int p2 = raw.indexOf('|', p1 + 1);
  if (p1 < 0 || p2 < 0) return rec;
  rec.timedIn = (raw.charAt(0) == 'I');
  rec.shiftDate = raw.substring(p1 + 1, p2);
  rec.email = raw.substring(p2 + 1);
  return rec;
}

bool saveShiftRecord(const String& uid, bool timedIn, const String& shiftDate, const String& email) {
  String raw = String(timedIn ? "I" : "O") + "|" + shiftDate + "|" + email;
  return prefs.putString(prefKeyForUid(uid).c_str(), raw) > 0;
}

// ---- WiFi Connection Handler ----
void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  WiFi.setTxPower(WIFI_POWER_11dBm);
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
    ntpSynced = setupNtp();
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

// ---- MFRC522 Health Check & Recovery ----
bool readerResponds() {
  for (int i = 0; i < 3; i++) {
    byte v = rfid.PCD_ReadRegister(MFRC522::VersionReg);
    lastVersionReg = v;
    if (v != 0x00 && v != 0xFF) return true;
    delay(5);
  }
  return false;
}

bool recoverReader() {
  SPI.end();
  delay(10);
  SPI.begin(SPI_SCK, SPI_MISO, SPI_MOSI, SS_PIN);

  pinMode(RST_PIN, OUTPUT);
  digitalWrite(RST_PIN, LOW);
  delay(20);
  digitalWrite(RST_PIN, HIGH);
  delay(60);

  rfid.PCD_Init();
  delay(20);
  return readerResponds();
}

// ---- Firestore runQuery helper ----
QueryResult firestoreQuery(const char* collectionId, const char* fieldPath, const String& value) {
  QueryResult result;

  if (WiFi.status() != WL_CONNECTED) {
    result.httpCode = -100;
    Serial.println("Firestore query skipped: WiFi not connected");
    return result;
  }

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(4000);
  http.setConnectTimeout(4000);
  String queryUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents:runQuery";

  if (!http.begin(client, queryUrl)) {
    result.httpCode = -101;
    Serial.println("Firestore query: http.begin() failed");
    return result;
  }
  http.addHeader("Content-Type", "application/json");

  JsonDocument doc;
  JsonObject structuredQuery = doc["structuredQuery"].to<JsonObject>();

  JsonArray from = structuredQuery["from"].to<JsonArray>();
  JsonObject collection = from.add<JsonObject>();
  collection["collectionId"] = collectionId;

  JsonObject whereObj = structuredQuery["where"].to<JsonObject>();
  JsonObject fieldFilter = whereObj["fieldFilter"].to<JsonObject>();
  fieldFilter["field"]["fieldPath"] = fieldPath;
  fieldFilter["op"] = "EQUAL";
  fieldFilter["value"]["stringValue"] = value;

  String requestBody;
  serializeJson(doc, requestBody);

  result.httpCode = http.POST(requestBody);
  if (result.httpCode == 200) {
    result.body = http.getString();
    result.ok = (result.body.length() > 0);
  }
  http.end();

  Serial.printf("Firestore query [%s] HTTP %d\n", collectionId, result.httpCode);
  return result;
}

// ---- Firebase Firestore Query: Match RFID Card UID with Employee Email ----
EmployeeMatch findEmployeeByRfid(const String& uid) {
  EmployeeMatch match;

  QueryResult q = firestoreQuery("users", "rfidCardId", uid);
  match.httpCode = q.httpCode;
  if (!q.ok) return match;

  JsonDocument resDoc;
  DeserializationError err = deserializeJson(resDoc, q.body);
  if (err) {
    Serial.print("JSON parse error (users): ");
    Serial.println(err.c_str());
    return match;
  }

  match.queryOk = true;

  if (resDoc.is<JsonArray>() && resDoc.size() > 0) {
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

  return match;
}

// ---- Check the employee's existing record(s) in the 'attendance' Collection ----
// Runs on EVERY tap. Firebase is the source of truth, per employee name.
AttendanceStatus getEmployeeAttendanceStatus(const String& employeeName, const String& currentShift) {
  AttendanceStatus status;
  if (employeeName.length() == 0) return status;

  QueryResult q = firestoreQuery("attendance", "employeeName", employeeName);
  if (!q.ok) return status;

  JsonDocument resDoc;
  DeserializationError err = deserializeJson(resDoc, q.body);
  if (err) return status;

  status.queryOk = true;

  if (!resDoc.is<JsonArray>()) return status;

  for (JsonObject res : resDoc.as<JsonArray>()) {
    if (res["document"].isNull()) continue;   // empty result entry (no match)

    JsonObject fields = res["document"]["fields"];
    // timeOut is written as {"nullValue": null} on Time In, so read the stringValue.
    // A missing stringValue (nullValue) becomes "".
    const char* tIn  = fields["timeIn"]["stringValue"] | "";
    const char* tOut = fields["timeOut"]["stringValue"] | "";
    String dateStr   = fields["date"]["timestampValue"] | "";

    bool hasTimeIn  = strlen(tIn) > 0;
    bool hasTimeOut = strlen(tOut) > 0;
    if (!hasTimeIn) continue;                 // reset/blank record: ignore

    if (!hasTimeOut) {
      status.hasOpenShift = true;
      String docPath = res["document"]["name"].as<String>();
      int lastSlash = docPath.lastIndexOf('/');
      if (lastSlash != -1) status.attendanceDocId = docPath.substring(lastSlash + 1);
      break;                                  // open shift takes priority
    }

    // Completed record: only counts if it belongs to the current shift
    String recShift = shiftDateFromIso(dateStr);
    if (recShift.length() == 0 || recShift == currentShift) {
      status.completedThisShift = true;
    }
  }

  return status;
}

// ---- Unified Direct Firestore Write to 'attendance' Collection ----
bool postAttendanceToFirebase(const String& uid, const String& employeeName,
                              const String& action, const String& status,
                              const String& email, const String& openDocId = "") {
  if (WiFi.status() != WL_CONNECTED) return false;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(4000);
  http.setConnectTimeout(4000);

  struct tm ti;
  getLocalTime(&ti, 0);
  String timeStr = getCurrentTimeString();

  // TIME_OUT: update ONLY the existing open record. Never create a new one.
  if (action == "TIME_OUT") {
    if (openDocId.length() == 0) return false;

    String patchUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents/attendance/" + openDocId + "?updateMask.fieldPaths=timeOut";
    if (!http.begin(client, patchUrl)) return false;
    http.addHeader("Content-Type", "application/json");

    JsonDocument doc;
    JsonObject fields = doc["fields"].to<JsonObject>();
    fields["timeOut"]["stringValue"] = timeStr;

    String requestBody;
    serializeJson(doc, requestBody);
    int httpCode = http.PATCH(requestBody);
    http.end();
    Serial.printf("Firestore attendance PATCH TIME_OUT HTTP %d\n", httpCode);
    return (httpCode == 200 || httpCode == 201);
  }

  // TIME_IN -> create a new single document in 'attendance' collection
  String postUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents/attendance";
  if (!http.begin(client, postUrl)) return false;
  http.addHeader("Content-Type", "application/json");

  JsonDocument doc;
  JsonObject fields = doc["fields"].to<JsonObject>();
  fields["employeeName"]["stringValue"] = employeeName;
  fields["timeIn"]["stringValue"] = timeStr;
  fields["timeOut"]["nullValue"] = nullptr;
  fields["status"]["stringValue"] = status.length() > 0 ? status : "Present";
  fields["method"]["stringValue"] = "RFID";
  fields["rfidCardId"]["stringValue"] = uid;

  char isoBuf[30];
  snprintf(isoBuf, sizeof(isoBuf), "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
           ti.tm_year + 1900, ti.tm_mon + 1, ti.tm_mday, ti.tm_hour, ti.tm_min, ti.tm_sec);
  fields["date"]["timestampValue"] = String(isoBuf);
  fields["createdAt"]["timestampValue"] = String(isoBuf);

  String requestBody;
  serializeJson(doc, requestBody);
  int httpCode = http.POST(requestBody);
  http.end();

  Serial.printf("Firestore attendance POST TIME_IN HTTP %d\n", httpCode);
  return (httpCode == 200 || httpCode == 201);
}

// ---- Firebase Firestore Push: Log RFID Scan Event for Registration ----
bool postRfidScanToFirebase(const String& uid, const String& employeeName = "") {
  if (WiFi.status() != WL_CONNECTED) return false;

  WiFiClientSecure client;
  client.setInsecure();

  HTTPClient http;
  http.setTimeout(3000);
  http.setConnectTimeout(3000);
  String postUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents/rfidScans";

  if (!http.begin(client, postUrl)) return false;
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

  // 0. Need WiFi to do anything
  if (WiFi.status() != WL_CONNECTED) {
    showError("No WiFi", "OFFLINE", "Tap again later");
    return;
  }

  // 1. Query Firestore for Employee matching rfidCardId
  EmployeeMatch emp = findEmployeeByRfid(uid);

  if (!emp.queryOk) {
    showError("Server Error", "Try Again", "Code " + String(emp.httpCode));
    return;
  }

  if (!emp.found) {
    postRfidScanToFirebase(uid, "");
    Serial.println("UNREGISTERED CARD. Tag posted for live registration.");
    showError("Unregistered Card", "Not Linked", "UID: " + uid);
    return;
  }

  if (emp.fullName.length() == 0) {
    showError("Card Error", "No Name", "UID: " + uid);
    return;
  }

  // 2. Check current Philippine time via NTP
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo, 0)) {
    showError(emp.fullName, "No Clock", "NTP not synced");
    return;
  }
  int minutes = timeinfo.tm_hour * 60 + timeinfo.tm_min;
  String timeStr = getCurrentTimeString();

  bool inTimeOutWindow = (minutes >= TIME_OUT_OPEN_MIN && minutes <= TIME_OUT_CLOSE_MIN);
  bool inTimeInWindow = (minutes >= TIME_IN_OPEN_MIN || minutes < TIME_OUT_OPEN_MIN);
  String shiftDate = currentShiftDate(minutes);

  // 3. Validate against the employee's existing record in Firebase on EVERY tap.
  //    If the check fails we never fall through to a write.
  AttendanceStatus attStatus = getEmployeeAttendanceStatus(emp.fullName, shiftDate);
  if (!attStatus.queryOk) {
    showError("Server Error", "Try Again", "Attendance check");
    return;
  }

  // Keep the flash mirror in sync with Firebase. If the Admin reset this employee
  // (record gone) or the card was re-linked, clear only THIS card's local state.
  ShiftRecord rec = loadShiftRecord(uid);
  bool firebaseHasRecord = attStatus.hasOpenShift || attStatus.completedThisShift;
  if ((rec.shiftDate.length() > 0 && !firebaseHasRecord) ||
      (rec.shiftDate.length() > 0 && rec.email != emp.email)) {
    Serial.println("Attendance reset or re-linked, clearing local state for " + emp.fullName);
    saveShiftRecord(uid, false, "", emp.email);
  }

  bool doTimeOut = false;
  String status = "";

  if (attStatus.hasOpenShift) {
    // Already timed in -> a new Time In is never allowed. Only Time Out, only in its window.
    if (inTimeOutWindow) {
      doTimeOut = true;
    } else if (minutes < TIME_OUT_OPEN_MIN || minutes >= TIME_IN_OPEN_MIN) {
      Serial.println("DUPLICATE TIME IN BLOCKED (open record exists): " + emp.fullName);
      showError(emp.fullName, "Time-out opens at 2:00am", "");
      return;
    } else {
      Serial.println("TIME OUT CLOSED: after 2:30 AM for " + emp.fullName);
      showError(emp.fullName, "Time Out Closed at 2:30 AM", "");
      return;
    }
  } else {
    // No open record. If this shift already has a completed record, block until Admin reset.
    if (attStatus.completedThisShift) {
      Serial.println("TIME IN BLOCKED (ALREADY COMPLETED): " + emp.fullName);
      showError(emp.fullName, "Already Timed In", "Need Admin Reset");
      return;
    }
    if (!inTimeInWindow) {
      Serial.println("TIME IN NOT OPEN: " + emp.fullName);
      showError(emp.fullName, "Time In Opens at 6:30 PM", "");
      return;
    }
    status = (minutes <= PRESENT_UNTIL_MIN) ? "Present" : "Late";
  }

  // 4. Write to the unified 'attendance' collection in Firestore
  String actionCode = doTimeOut ? "TIME_OUT" : "TIME_IN";
  if (!postAttendanceToFirebase(uid, emp.fullName, actionCode, status, emp.email, attStatus.attendanceDocId)) {
    showError(emp.fullName, "NOT SAVED", "Tap again");
    return;
  }

  // 5. Commit local mirror only after Firebase save succeeded
  if (!saveShiftRecord(uid, !doTimeOut, shiftDate, emp.email)) {
    Serial.println("WARNING: could not save local attendance state to flash.");
  }

  // 6. Display success result on OLED & play sound
  String actionLabel = doTimeOut ? "TIME OUT " + timeStr : "TIME IN " + timeStr;
  Serial.printf("ATTENDANCE SUCCESS! Employee: %s | Action: %s | Status: %s\n",
                emp.fullName.c_str(), actionLabel.c_str(), status.c_str());
  String line3 = doTimeOut ? (emp.email.length() > 0 ? emp.email : uid) : status;
  showScreen(emp.fullName, actionLabel, line3);
  beepOk();
}

// ---- Setup: Automatic Initialization on Power Up ----
void setup() {
  Serial.begin(115200);
  Serial.println("\n--- Overnight Cafe RFID Attendance Scanner ---");

  bool brownedOut = (esp_reset_reason() == ESP_RST_BROWNOUT);

  // Open persistent attendance state storage
  prefs.begin("attendance", false);

  // Initialize OLED
  Wire.begin(OLED_SDA, OLED_SCL);
  oledOk = display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);
  Serial.println(oledOk ? "OLED Display Ready." : "OLED Display not detected.");
  showScreen("Overnight Cafe", "Starting...");

  if (brownedOut) {
    Serial.println("WARNING: last reset was a BROWNOUT.");
    showScreen("LOW POWER", "Brownout", "Check USB / cap");
    delay(2000);
  }

  // Initialize MFRC522 RFID Reader Hardware
  SPI.begin(SPI_SCK, SPI_MISO, SPI_MOSI, SS_PIN);
  rfid.PCD_Init();
  if (!readerResponds()) {
    Serial.println("MFRC522 not detected at startup, trying recovery...");
    readerOk = recoverReader();
  }
  if (readerOk) {
    rfid.PCD_DumpVersionToSerial();
  } else {
    Serial.printf("MFRC522 STILL not responding (VersionReg=0x%02X).\n", lastVersionReg);
    showScreen("READER ERROR", "Not Found", "Check wiring");
    delay(1500);
  }

  rfid.PCD_AntennaOff();
  connectWifi();
  rfid.PCD_AntennaOn();

  showReadyScreen();
  Serial.println("System Ready. Continuous loop active.");
}

// ---- Main Continuous Polling Loop ----
void loop() {
  unsigned long now = millis();

  // Reconnect WiFi in background if disconnected
  if (WiFi.status() != WL_CONNECTED) {
    static unsigned long lastRetry = 0;
    if (now - lastRetry > 15000) {
      lastRetry = now;
      Serial.println("WiFi lost, reconnecting...");
      WiFi.reconnect();
    }
  }

  // Retry NTP in background if the clock was never synced
  if (!ntpSynced && WiFi.status() == WL_CONNECTED) {
    static unsigned long lastNtpTry = 0;
    if (now - lastNtpTry > 30000) {
      lastNtpTry = now;
      configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");
      struct tm t;
      ntpSynced = getLocalTime(&t, 1000);
      Serial.println(ntpSynced ? "NTP synced (background)." : "NTP still not synced.");
    }
  }

  // Non-blocking screen reset timer
  static unsigned long screenResetTime = 0;
  static bool screenNeedsReset = false;
  if (screenNeedsReset && now >= screenResetTime) {
    screenNeedsReset = false;
    if (readerOk) showReadyScreen();
  }

  // Reader health check (no blind re-init)
  static unsigned long lastHealthCheck = 0;
  unsigned long healthInterval = readerOk ? 5000 : 2000;
  if (now - lastHealthCheck > healthInterval) {
    lastHealthCheck = now;

    if (!readerResponds()) {
      readerFailStreak++;
      Serial.printf("MFRC522 not responding (fail #%d, VersionReg=0x%02X), recovering...\n", readerFailStreak, lastVersionReg);

      if (readerOk) {
        readerOk = false;
        screenNeedsReset = false;
        showScreen("READER ERROR", "Recovering", "Check wiring/power");
      }

      if (recoverReader()) {
        readerOk = true;
        readerFailStreak = 0;
        Serial.println("MFRC522 recovered.");
        showReadyScreen();
      } else if (readerFailStreak >= 5) {
        Serial.println("MFRC522 unrecoverable, restarting ESP32...");
        showScreen("READER ERROR", "Restarting", "");
        delay(1000);
        ESP.restart();
      }
    } else {
      readerFailStreak = 0;
    }
  }

  // Do not poll a dead reader
  if (!readerOk) return;

  static bool latched = false;
  static unsigned long lastSeen = 0;

  byte atqa[2];
  byte atqaSize = sizeof(atqa);
  MFRC522::StatusCode st = rfid.PICC_WakeupA(atqa, &atqaSize);
  bool present = (st == MFRC522::STATUS_OK || st == MFRC522::STATUS_COLLISION);

  if (present && rfid.PICC_ReadCardSerial()) {
    String uid = readUid();

    // Always halt and stop crypto right after reading the UID
    rfid.PICC_HaltA();
    rfid.PCD_StopCrypto1();

    if (!latched && uid.length() > 0) {
      latched = true;

      rfid.PCD_AntennaOff();
      processCardScan(uid);
      rfid.PCD_AntennaOn();

      if (!readerResponds()) {
        Serial.println("MFRC522 lost after scan, recovering...");
        readerOk = recoverReader();
        if (!readerOk) lastHealthCheck = 0;
      }

      screenResetTime = millis() + 2000;
      screenNeedsReset = true;
    }

    lastSeen = millis();
    return;
  }

  if (latched && millis() - lastSeen > 500) {
    latched = false;
    Serial.println("Card removed, ready for next scan.");
  }
}