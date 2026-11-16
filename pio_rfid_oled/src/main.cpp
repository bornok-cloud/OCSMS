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

// Buzzer test switch: 0 = silent (for testing if the buzzer causes the MFRC522 to die),
// 1 = buzzer enabled. Set to 1 again once the reader is stable.
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
byte lastVersionReg = 0;      // last VersionReg value read (0x00/0xFF = no answer, for diagnosis)

// ---- Employee Record & Attendance Structures ----
struct EmployeeMatch {
    bool queryOk = false;   // false = network/server/parse error (NOT the same as "not found")
    int httpCode = 0;
    bool found = false;
    String fullName = "";
    String email = "";
    String id = "";
};

struct AttendanceStatus {
    bool queryOk = false;
    bool hasOpenShift = false;
    String attendanceDocId = "";
};

struct QueryResult {
    bool ok = false;
    int httpCode = 0;
    String body = "";
};

// Per-employee shift record, keyed by RFID UID and tied to the registered email.
// shiftDate = calendar date (YYYYMMDD) on which the shift STARTED (the 6:30 PM date).
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
    delay(ms);  // keep the same timing, but no sound / no buzzer current
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
// Returns the YYYYMMDD of the day the CURRENT shift started. Before 6:30 PM we are
// still inside (or after) the shift that began the previous evening, so use yesterday.
// This is what makes the 6:30 PM -> 2:30 AM overnight cycle work across midnight.
String currentShiftDate(int minutesOfDay) {
    time_t nowT = time(nullptr);
    if (minutesOfDay < TIME_IN_OPEN_MIN) nowT -= 86400;
    struct tm t;
    localtime_r(&nowT, &t);
    char buf[9];
    snprintf(buf, sizeof(buf), "%04d%02d%02d", t.tm_year + 1900, t.tm_mon + 1, t.tm_mday);
    return String(buf);
}

// ---- Per-Employee Attendance State (stored in flash by RFID UID) ----
// Stored value format: "I|YYYYMMDD|email"  (timed in)  or  "O|YYYYMMDD|email"  (timed out)
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
    // Lower TX power to reduce current spikes that can brown out a weak supply
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
// The VersionReg reads 0x00 or 0xFF when the chip is not answering on SPI
// (wiring problem, power sag, or the chip locked up). Retry a few times
// so a single bad SPI read is not treated as a failure.
bool readerResponds() {
    for (int i = 0; i < 3; i++) {
        byte v = rfid.PCD_ReadRegister(MFRC522::VersionReg);
        lastVersionReg = v;
        if (v != 0x00 && v != 0xFF) return true;
        delay(5);
    }
    return false;
}

// Full recovery: restart SPI bus, pulse the hardware RST pin, re-init the chip.
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

// ---- Firestore runQuery helper (single place for all HTTP error handling) ----
// Returns ok=true only when the server answered HTTP 200.
QueryResult firestoreQuery(const char* collectionId, const char* fieldPath, const String& value) {
    QueryResult result;

    if (WiFi.status() != WL_CONNECTED) {
        result.httpCode = -100;  // not connected
        Serial.println("Firestore query skipped: WiFi not connected");
        return result;
    }

    WiFiClientSecure client;
    client.setInsecure();  // SSL Connection for HTTPS Firestore API

    HTTPClient http;
    http.setTimeout(4000);
    http.setConnectTimeout(4000);
    String queryUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents:runQuery";

    if (!http.begin(client, queryUrl)) {
        result.httpCode = -101;  // begin failed
        Serial.println("Firestore query: http.begin() failed");
        return result;
    }
    http.addHeader("Content-Type", "application/json");

    // Construct Firestore runQuery JSON
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
    if (!q.ok) return match;  // queryOk stays false -> network/server problem

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

// ---- Check Employee Open Attendance Status ----
// NOTE: no longer used by processCardScan(); the schedule logic now tracks each
// employee's state per RFID UID/email (see ShiftRecord). Kept for reference.
AttendanceStatus getEmployeeAttendanceStatus(const String& employeeName) {
    AttendanceStatus status;
    if (employeeName.length() == 0) return status;

    QueryResult q = firestoreQuery("attendance", "employeeName", employeeName);
    if (!q.ok) return status;  // queryOk stays false

    JsonDocument resDoc;
    DeserializationError err = deserializeJson(resDoc, q.body);
    if (err) {
        Serial.print("JSON parse error (attendance): ");
        Serial.println(err.c_str());
        return status;
    }

    status.queryOk = true;

    if (resDoc.is<JsonArray>() && resDoc.size() > 0) {
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

    return status;
}

// ---- Check if Employee Already Completed Shift Today ----
// NOTE: no longer used by processCardScan() (duplicate Time In/Out is now prevented
// by the per-UID ShiftRecord). Kept for reference.
bool hasAlreadyTappedToday(const String& employeeName) {
    if (employeeName.length() == 0) return false;

    QueryResult q = firestoreQuery("attendance", "employeeName", employeeName);
    if (!q.ok) return false;

    JsonDocument resDoc;
    DeserializationError err = deserializeJson(resDoc, q.body);
    if (err) return false;

    if (resDoc.is<JsonArray>() && resDoc.size() > 0) {
        for (JsonObject res : resDoc.as<JsonArray>()) {
            if (!res["document"].isNull()) {
                JsonObject fields = res["document"]["fields"];
                if (!fields["timeIn"].isNull() && fields["timeOut"].isNull() && !isTimeoutWindow()) {
                    return true;
                }
            }
        }
    }

    return false;
}

// ---- Firebase Firestore Push: Log RFID Scan Event ----
// action = "TIME_IN" / "TIME_OUT", status = "Present" / "Late" (Time In only).
// These extra fields are only added when provided, so unregistered-card logging is unchanged.
bool postRfidScanToFirebase(const String& uid, const String& employeeName = "",
                            const String& action = "", const String& status = "",
                            const String& email = "") {
    if (WiFi.status() != WL_CONNECTED) return false;

    WiFiClientSecure client;
    client.setInsecure();

    HTTPClient http;
    http.setTimeout(4000);
    http.setConnectTimeout(4000);
    String postUrl = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) + "/databases/(default)/documents/rfidScans";

    if (!http.begin(client, postUrl)) {
        Serial.println("Firestore push: http.begin() failed");
        return false;
    }
    http.addHeader("Content-Type", "application/json");

    JsonDocument doc;
    JsonObject fields = doc["fields"].to<JsonObject>();
    fields["rfidTag"]["stringValue"] = uid;
    if (employeeName.length() > 0) {
        fields["employeeName"]["stringValue"] = employeeName;
    }
    if (email.length() > 0) {
        fields["email"]["stringValue"] = email;
    }
    if (action.length() > 0) {
        fields["action"]["stringValue"] = action;
    }
    if (status.length() > 0) {
        fields["status"]["stringValue"] = status;
    }
    struct tm ti;
    if (action.length() > 0 && getLocalTime(&ti, 0)) {
        char tbuf[24];
        snprintf(tbuf, sizeof(tbuf), "%04d-%02d-%02d %02d:%02d:%02d",
                 ti.tm_year + 1900, ti.tm_mon + 1, ti.tm_mday, ti.tm_hour, ti.tm_min, ti.tm_sec);
        fields["scanTime"]["stringValue"] = String(tbuf);
    }

    String requestBody;
    serializeJson(doc, requestBody);

    int httpCode = http.POST(requestBody);
    http.end();

    Serial.printf("Firestore rfidScans push HTTP %d\n", httpCode);
    return (httpCode == 200 || httpCode == 201);
}

// ---- Handle Scanned RFID Card Event ----
// Schedule (Asia/Manila), shift runs 6:30 PM -> 2:30 AM:
//   Time In : opens 6:30 PM. 6:30-6:40 PM = Present, 6:41 PM onwards = Late.
//   Time Out: only 2:00 AM - 2:30 AM. Before 2:00 AM -> "Time Out Opens at 2:00 AM",
//             after 2:30 AM -> "Time Out Closed".
//   After Time In  -> next valid action is Time Out (in its window only).
//   After Time Out -> next valid action is Time In from 6:30 PM.
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
        // Network/server failure - do NOT report this as an unregistered card
        showError("Server Error", "Try Again", "Code " + String(emp.httpCode));
        return;
    }

    if (!emp.found) {
        postRfidScanToFirebase(uid, "");
        Serial.println("UNREGISTERED CARD.");
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
    int minutes = timeinfo.tm_hour * 60 + timeinfo.tm_min;  // minutes since midnight (PH time)
    String timeStr = getCurrentTimeString();

    bool inTimeOutWindow = (minutes >= TIME_OUT_OPEN_MIN && minutes <= TIME_OUT_CLOSE_MIN);
    // Time In is accepted from 6:30 PM until the next 2:00 AM (anything after 6:40 PM is Late)
    bool inTimeInWindow = (minutes >= TIME_IN_OPEN_MIN || minutes < TIME_OUT_OPEN_MIN);

    // 3. Load this employee's state (keyed by RFID UID, tied to registered email)
    String shiftDate = currentShiftDate(minutes);
    ShiftRecord rec = loadShiftRecord(uid);
    if (rec.shiftDate.length() > 0 && rec.email != emp.email) {
        Serial.println("Card re-linked to a different email, resetting stored state.");
        rec = ShiftRecord();
    }
    bool sameShift = (rec.shiftDate.length() > 0 && rec.shiftDate == shiftDate);
    bool openShift = (sameShift && rec.timedIn);
    bool completedShift = (sameShift && !rec.timedIn);

    bool doTimeOut = false;
    String status = "";

    if (openShift) {
        // Already timed in for this shift -> only Time Out is valid, and only in its window
        if (inTimeOutWindow) {
            doTimeOut = true;
        } else if (minutes < TIME_OUT_OPEN_MIN || minutes >= TIME_IN_OPEN_MIN) {
            Serial.println("TIME OUT BLOCKED: before 2:00 AM for " + emp.fullName);
            showError(emp.fullName, "Time Out Opens", "at 2:00 AM");
            return;
        } else {
            Serial.println("TIME OUT CLOSED: after 2:30 AM for " + emp.fullName);
            showError(emp.fullName, "Time Out Closed", "Ended 2:30 AM");
            return;
        }
    } else {
        // No open shift -> only Time In is valid, and only from 6:30 PM
        if (completedShift || !inTimeInWindow) {
            Serial.println("TIME IN NOT OPEN: " + emp.fullName);
            showError(emp.fullName, "Time In Opens", "at 6:30 PM");
            return;
        }
        status = (minutes <= PRESENT_UNTIL_MIN) ? "Present" : "Late";
    }

    // 4. Push Scan to Firebase for real-time app sync & attendance logging
    String actionCode = doTimeOut ? "TIME_OUT" : "TIME_IN";
    if (!postRfidScanToFirebase(uid, emp.fullName, actionCode, status, emp.email)) {
        showError(emp.fullName, "NOT SAVED", "Tap again");
        return;  // state NOT changed, so the employee can simply tap again
    }

    // 5. Commit the new state only after the scan was saved
    if (!saveShiftRecord(uid, !doTimeOut, shiftDate, emp.email)) {
        Serial.println("WARNING: could not save local attendance state to flash.");
    }

    // 6. Display Success Result on OLED & Play Sound
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
        Serial.println("WARNING: last reset was a BROWNOUT. The power supply is too weak (see wiring notes).");
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
        Serial.printf("MFRC522 STILL not responding (VersionReg=0x%02X). Check wiring and 3.3V power.\n", lastVersionReg);
        showScreen("READER ERROR", "Not Found", "Check wiring");
        delay(1500);
    }

    // Turn the RFID antenna off while WiFi connects to reduce peak current
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

    // Reader health check (no blind re-init). Check faster while it is failing.
    static unsigned long lastHealthCheck = 0;
    unsigned long healthInterval = readerOk ? 5000 : 2000;
    if (now - lastHealthCheck > healthInterval) {
        lastHealthCheck = now;

        if (!readerResponds()) {
            readerFailStreak++;
            // VersionReg 0x00 = no power / MISO held low, 0xFF = MISO floating / SS not connected
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

    // Do not poll a dead reader (avoids garbage SPI reads)
    if (!readerOk) return;

    // latched = true while the same physical card is still on the reader.
    // A halted card ignores REQA (PICC_IsNewCardPresent), so we use WUPA instead,
    // which halted cards DO answer. That lets us tell "still there" from "removed".
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

            // Antenna off while doing WiFi/TLS work to cut current draw (prevents brownouts)
            rfid.PCD_AntennaOff();
            processCardScan(uid);
            rfid.PCD_AntennaOn();

            // If the reader got upset by the power dip, flag it so the health check recovers it
            if (!readerResponds()) {
                Serial.println("MFRC522 lost after scan, recovering...");
                readerOk = recoverReader();
                if (!readerOk) lastHealthCheck = 0;
            }

            // Schedule screen reset 2 seconds later (non-blocking)
            screenResetTime = millis() + 2000;
            screenNeedsReset = true;
        }

        lastSeen = millis();
        return;
    }

    // No card answered for 500 ms = card was removed, allow the next scan
    if (latched && millis() - lastSeen > 500) {
        latched = false;
        Serial.println("Card removed, ready for next scan.");
    }
}