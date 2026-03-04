#include <Arduino.h>
#include <EEPROM.h>
#include <ctype.h>
#include <esp_system.h>

// ===================== BLE (built-in core) =====================
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// =====================================================
// ESP32 DevKit V4 - 16CH Relay Light Matrix
// BLE UART (NUS) + Serial
//
// Commands:
// 1..24 | SPEED 20..5000 | LOW | MED | HIGH | IDLE | STOP | IDLE n
// Relay board: "LOW level trigger" => RELAY_ACTIVE_LOW = true
// EEPROM ESP32: EEPROM.begin(size) + EEPROM.commit()
// =====================================================

// -------------------- CONFIG --------------------
#define USE_BLE 1
static const char* BLE_NAME = "LM-ESP32";

// NUS UUIDs
static const char* SVC_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* RX_UUID  = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* TX_UUID  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

// ===================== RELAY PINS =====================
#define N_CH 16
const bool RELAY_ACTIVE_LOW = true;

const uint8_t relayPins[N_CH] = {
  13, 14, 27, 26, 25, 33, 32, 16,
  17, 18, 19, 21, 22, 4, 5, 15
};

// ===================== EEPROM =====================
const int EEPROM_SIZE = 64;
const int EEPROM_ADDR_IDLE = 0;

// ===================== TIMING =====================
unsigned long lastTick = 0;
unsigned long intervalMs = 200;

const unsigned long SPEED_LOW_MS  = 200;
const unsigned long SPEED_MED_MS  = 160;
const unsigned long SPEED_HIGH_MS = 120;

// ===================== MODE ENUM =====================
enum Mode : uint8_t {
  STOP_MODE = 0,
  M1_L2R = 1,
  M2_R2L = 2,
  M3_CENTER4_EXPAND_BLINK = 3,
  M4_HALF_SWEEP = 4,
  M5_PINGPONG_2LAMPS = 5,
  M6_INOUT_PINGPONG_PAIRS = 6,
  M7_PAIR_PINGPONG = 7,
  M8_HORIZONTAL_PINGPONG = 8,
  M9_FILL_UNFILL_L2R = 9,
  M10_BLINK_TOP = 10,
  M11_FILL_UNFILL_R2L = 11,
  M12_BLINK_BOTTOM = 12,
  M13_ODD_EVEN = 13,
  M14_CUSTOM_JUMP_SEQUENCE = 14,
  M15_TRIPLET_SHIFT = 15,
  M16_RANDOM_SPARKLE = 16,
  M17_CORNERS_TO_MID_PINGPONG = 17,
  M18_ZIGZAG = 18,
  M19_QUADRANT = 19,
  M20_WAVE_2STEP = 20,
  M21_EXPAND_TOP_FILL_UNFILL = 21,
  M22_EXPAND_BOTTOM_FILL_UNFILL = 22,
  M23_SHOW_A = 23,
  M24_SHOW_B = 24
};

Mode mode = STOP_MODE;

// ===================== STATE =====================
uint8_t idleMode = 3;

const uint8_t BLINK3_COUNT = 4;
const uint8_t BLINK3_STEPS = BLINK3_COUNT * 2;
const unsigned long pauseMs_blink3 = 200;

unsigned long blink3_pauseUntil = 0;
bool blink3_inPause = false;
uint8_t blink3_step = 0;

// Startup sequence
bool startupActive = true;
uint8_t startupCyclesDone = 0;
const uint8_t STARTUP_CYCLES_TARGET = 2;

// Mode 3
const unsigned long pauseMs_mode3 = 200;
unsigned long pauseUntil = 0;
bool mode3_inPause = false;
uint8_t mode3_layer = 0;
uint8_t mode3_blinkStep = 0;

// Mode 4
uint8_t mode4_idx = 0;

// Mode 5/6/7/8
int8_t mode5_dir = 1; uint8_t mode5_pos = 0;
int8_t mode6_dir = 1; uint8_t mode6_pos = 0;
int8_t mode7_dir = 1; uint8_t mode7_step = 0;
int8_t mode8_dir = 1; uint8_t mode8_step = 0;

// Mode 14
uint8_t mode14_step = 0;

// Mode 17
int8_t mode17_dir = 1; uint8_t mode17_step = 0;

// Generic step
uint8_t stepIdx = 0;

// ===================== SHOW ENGINE =====================
uint8_t show_seg = 0;
bool show_init = true;
unsigned long show_segUntil = 0;

uint8_t show_step = 0;
uint8_t show_m17_step = 0;
int8_t  show_m17_dir  = 1;
bool    show_m17_hitMax = false;

uint8_t show_m6_pos = 0;   int8_t show_m6_dir = 1;
uint8_t show_m8_step = 0;  int8_t show_m8_dir = 1;
uint8_t show_m4_idx = 0;

uint8_t show_quad = 0;
uint8_t show_oddEven = 0;

// ===================== RELAY HELPERS =====================
static inline void writePin(uint8_t pin, bool on) {
  digitalWrite(pin, (RELAY_ACTIVE_LOW ? (on ? LOW : HIGH) : (on ? HIGH : LOW)));
}

static inline void setMask(uint32_t mask) {
  for (uint8_t i = 0; i < N_CH; i++) {
    writePin(relayPins[i], (mask >> i) & 0x01);
  }
}

static inline uint32_t allOnMask() { return ((1UL << N_CH) - 1UL); }

static uint32_t oddMask() {
  uint32_t m = 0;
  for (uint8_t i = 0; i < N_CH; i += 2) m |= (1UL << i);
  return m;
}
static uint32_t evenMask() {
  uint32_t m = 0;
  for (uint8_t i = 1; i < N_CH; i += 2) m |= (1UL << i);
  return m;
}
static uint32_t rangeMask(uint8_t leftIdx, uint8_t rightIdx) {
  uint32_t m = 0;
  for (uint8_t i = leftIdx; i <= rightIdx; i++) m |= (1UL << i);
  return m;
}

// Layout helper: 1-8 kiri, 9-16 kanan
static inline uint32_t rowPairMask(uint8_t row) {
  return (1UL << row) | (1UL << (8 + row));
}
static uint32_t rowsRangeMask(uint8_t a, uint8_t b) {
  uint32_t m = 0;
  for (uint8_t r = a; r <= b; r++) m |= rowPairMask(r);
  return m;
}
static inline uint32_t quadrantMask(uint8_t q) {
  uint8_t start = q * 4;
  return rangeMask(start, start + 3);
}

// ===================== BLE LINE QUEUE =====================
#if USE_BLE
static BLECharacteristic* pTx = nullptr;
static BLECharacteristic* pRx = nullptr;
static bool bleConnected = false;

#define BLE_Q_SIZE 256
static char bleQ[BLE_Q_SIZE];
static volatile uint16_t bleHead = 0, bleTail = 0;
static portMUX_TYPE bleMux = portMUX_INITIALIZER_UNLOCKED;

static inline void bleEnq(char c){
  uint16_t next = (uint16_t)((bleHead + 1) % BLE_Q_SIZE);
  if(next == bleTail) return;
  bleQ[bleHead] = c;
  bleHead = next;
}
static bool bleDeq(char &c){
  if(bleTail == bleHead) return false;
  c = bleQ[bleTail];
  bleTail = (uint16_t)((bleTail + 1) % BLE_Q_SIZE);
  return true;
}

static void bleSendLine(const char* s){
  if(!bleConnected || !pTx) return;
  pTx->setValue((uint8_t*)s, strlen(s));
  pTx->notify();
}

class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleConnected = true; }
  void onDisconnect(BLEServer* server) override {
    bleConnected = false;
    delay(50);
    server->getAdvertising()->start();
  }
};

class RxCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String v = c->getValue();
    if (v.length() == 0) return;

    bool hasNL = false;

    portENTER_CRITICAL(&bleMux);
    for (int i = 0; i < v.length(); i++) {
      char ch = v[i];
      bleEnq(ch);
      if (ch == '\n') hasNL = true;
    }
    if (!hasNL) bleEnq('\n');
    portEXIT_CRITICAL(&bleMux);
  }
};

static void bleInit(){
  BLEDevice::init(BLE_NAME);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCB());

  BLEService* svc = server->createService(SVC_UUID);

  pTx = svc->createCharacteristic(
    TX_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTx->addDescriptor(new BLE2902());

  pRx = svc->createCharacteristic(
    RX_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pRx->setCallbacks(new RxCB());

  svc->start();

  BLEAdvertising* adv = server->getAdvertising();
  adv->addServiceUUID(SVC_UUID);
  adv->setScanResponse(true);
  adv->start();
}
#endif

// ===================== SHOW RESET =====================
static void showResetAll() {
  show_seg = 0;
  show_init = true;
  show_segUntil = 0;

  show_step = 0;
  show_m17_step = 0;
  show_m17_dir = 1;
  show_m17_hitMax = false;

  show_m6_pos = 0; show_m6_dir = 1;
  show_m8_step = 0; show_m8_dir = 1;
  show_m4_idx = 0;

  show_quad = 0;
  show_oddEven = 0;
}
static inline void restartShow() { showResetAll(); }

// ===================== MODE/EEPROM =====================
static bool isAllowedMode(int m) { return (m >= 1 && m <= 24); }

static void resetStates() {
  stepIdx = 0;
  lastTick = 0;

  blink3_step = 0;
  blink3_inPause = false;
  blink3_pauseUntil = 0;

  mode3_layer = 0;
  mode3_blinkStep = 0;
  mode3_inPause = false;
  pauseUntil = 0;

  mode4_idx = 0;

  mode5_dir = 1; mode5_pos = 0;
  mode6_dir = 1; mode6_pos = 0;

  mode7_dir = 1; mode7_step = 0;
  mode8_dir = 1; mode8_step = 0;

  mode14_step = 0;
  mode17_dir = 1; mode17_step = 0;

  showResetAll();
}

static void setMode(Mode m) {
  mode = m;
  resetStates();

  Serial.print("MODE = ");
  if (m == STOP_MODE) Serial.println("STOP");
  else Serial.println((int)m);

#if USE_BLE
  char msg[24];
  if (m == STOP_MODE) snprintf(msg, sizeof(msg), "MODE=STOP\n");
  else snprintf(msg, sizeof(msg), "MODE=%d\n", (int)m);
  bleSendLine(msg);
#endif
}

static void goIdle() { setMode((Mode)idleMode); }

static void loadIdleFromEEPROM() {
  uint8_t v = EEPROM.read(EEPROM_ADDR_IDLE);
  if (isAllowedMode(v)) idleMode = v;
  else idleMode = 3;
}

static void saveIdleToEEPROM(uint8_t m) {
  uint8_t old = EEPROM.read(EEPROM_ADDR_IDLE);
  if (old != m) {
    EEPROM.write(EEPROM_ADDR_IDLE, m);
    EEPROM.commit();
  }
  idleMode = m;

  Serial.print("IDLE = ");
  Serial.println(idleMode);

#if USE_BLE
  char msg[24];
  snprintf(msg, sizeof(msg), "IDLE=%d\n", (int)idleMode);
  bleSendLine(msg);
#endif
}

// ===================== PATTERN RUNNER =====================
static void tickPattern() {
  if (mode == STOP_MODE) return;

  unsigned long now = millis();
  if (now - lastTick < intervalMs) return;
  lastTick = now;

  uint32_t mask = 0;

  switch (mode) {
    case M1_L2R:
      mask = (1UL << stepIdx);
      stepIdx = (stepIdx + 1) % N_CH;
      break;

    case M2_R2L: {
      uint8_t p = (N_CH - 1) - stepIdx;
      mask = (1UL << p);
      stepIdx = (stepIdx + 1) % N_CH;
      break;
    }

    case M3_CENTER4_EXPAND_BLINK: {
      if (mode3_inPause) {
        mask = 0;
        if (now >= pauseUntil) mode3_inPause = false;
        setMask(mask);
        return;
      }

      int midLeft  = (N_CH / 2) - 1;
      int midRight = (N_CH / 2);
      int left  = (midLeft  - 1) - (int)mode3_layer * 2;
      int right = (midRight + 1) + (int)mode3_layer * 2;
      if (left < 0) left = 0;
      if (right > (N_CH - 1)) right = N_CH - 1;

      uint32_t layerMask = rangeMask((uint8_t)left, (uint8_t)right);
      bool on = (mode3_blinkStep % 2 == 0);
      mask = on ? layerMask : 0;

      mode3_blinkStep++;
      if (mode3_blinkStep >= BLINK3_STEPS) {
        mode3_blinkStep = 0;
        mode3_inPause = true;
        pauseUntil = now + pauseMs_mode3;

        mode3_layer++;
        if (mode3_layer >= 4) mode3_layer = 0;
      }
      break;
    }

    case M4_HALF_SWEEP: {
      static const uint8_t seq[] = {
        15,14,13,12,11,10,9,8,
        9,10,11,
        4,5,6,7,
        6,5,4,3,2,1,0,
        1,2,3,
        12,13,14
      };
      const uint8_t L = sizeof(seq) / sizeof(seq[0]);
      mask = (1UL << seq[mode4_idx]);
      mode4_idx++;
      if (mode4_idx >= L) mode4_idx = 0;
      break;
    }

    case M5_PINGPONG_2LAMPS:
      mask = (1UL << mode5_pos) | (1UL << (mode5_pos + 1));
      if (mode5_pos == 0) mode5_dir = 1;
      else if (mode5_pos == (N_CH - 2)) mode5_dir = -1;
      mode5_pos = (uint8_t)(mode5_pos + mode5_dir);
      break;

    case M6_INOUT_PINGPONG_PAIRS: {
      static const uint8_t seq[8] = {0, 14, 2, 12, 4, 10, 6, 8};
      uint8_t left = seq[mode6_pos];
      mask = (1UL << left) | (1UL << (left + 1));

      if (mode6_pos == 0) mode6_dir = 1;
      else if (mode6_pos == 7) mode6_dir = -1;
      mode6_pos = (uint8_t)(mode6_pos + mode6_dir);
      break;
    }

    case M7_PAIR_PINGPONG: {
      uint8_t left  = mode7_step;
      uint8_t right = 15 - mode7_step;
      mask = (1UL << left) | (1UL << right);

      if (mode7_step == 0) mode7_dir = 1;
      else if (mode7_step == 7) mode7_dir = -1;
      mode7_step = (uint8_t)(mode7_step + mode7_dir);
      break;
    }

    case M8_HORIZONTAL_PINGPONG: {
      static const uint8_t L[8] = { 0, 1, 2, 3, 11, 10, 9, 8 };
      static const uint8_t R[8] = { 7, 6, 5, 4, 12, 13, 14, 15 };
      uint8_t li = L[mode8_step];
      uint8_t ri = R[mode8_step];
      mask = (1UL << li) | (1UL << ri);

      if (mode8_step == 0) mode8_dir = 1;
      else if (mode8_step == 7) mode8_dir = -1;
      mode8_step = (uint8_t)(mode8_step + mode8_dir);
      break;
    }

    case M9_FILL_UNFILL_L2R: {
      const uint8_t N = N_CH;
      uint32_t full = allOnMask();

      if (stepIdx < N) mask = (1UL << (stepIdx + 1)) - 1UL;
      else {
        uint8_t k = stepIdx - N;
        uint32_t cut = (k == 0) ? 0UL : ((1UL << k) - 1UL);
        mask = full & ~cut;
      }
      stepIdx++;
      if (stepIdx > (2 * N)) stepIdx = 0;
      break;
    }

    case M10_BLINK_TOP: {
      const uint32_t TOP_MASK = 0xE007UL;
      if (blink3_inPause) {
        mask = 0;
        if (now >= blink3_pauseUntil) blink3_inPause = false;
        break;
      }
      bool on = (blink3_step % 2 == 0);
      mask = on ? TOP_MASK : 0UL;

      blink3_step++;
      if (blink3_step >= BLINK3_STEPS) {
        blink3_step = 0;
        blink3_inPause = true;
        blink3_pauseUntil = now + pauseMs_blink3;
      }
      break;
    }

    case M11_FILL_UNFILL_R2L: {
      uint8_t s = stepIdx % 8;
      if (s == 0)      mask = rowsRangeMask(3, 4);
      else if (s == 1) mask = rowsRangeMask(2, 5);
      else if (s == 2) mask = rowsRangeMask(1, 6);
      else if (s == 3) mask = rowsRangeMask(0, 7);
      else if (s == 4) mask = rowsRangeMask(1, 6);
      else if (s == 5) mask = rowsRangeMask(2, 5);
      else if (s == 6) mask = rowsRangeMask(3, 4);
      else             mask = 0;

      stepIdx = (stepIdx + 1) % 8;
      break;
    }

    case M12_BLINK_BOTTOM: {
      const uint32_t BOTTOM_MASK = 0x07E0UL;
      if (blink3_inPause) {
        mask = 0;
        if (now >= blink3_pauseUntil) blink3_inPause = false;
        break;
      }
      bool on = (blink3_step % 2 == 0);
      mask = on ? BOTTOM_MASK : 0UL;

      blink3_step++;
      if (blink3_step >= BLINK3_STEPS) {
        blink3_step = 0;
        blink3_inPause = true;
        blink3_pauseUntil = now + pauseMs_blink3;
      }
      break;
    }

    case M13_ODD_EVEN:
      mask = (stepIdx == 0) ? oddMask() : evenMask();
      stepIdx = (stepIdx + 1) % 2;
      break;

    case M14_CUSTOM_JUMP_SEQUENCE: {
      static const uint8_t seq[16] = {0,1,2,3, 11,10,9,8, 15,14,13,12, 4,5,6,7};
      mask = (1UL << seq[mode14_step]);
      mode14_step++;
      if (mode14_step >= 16) mode14_step = 0;
      break;
    }

    case M15_TRIPLET_SHIFT: {
      uint8_t phase = stepIdx % 3;
      uint32_t m = 0;
      for (uint8_t i = 0; i < N_CH; i++) if ((i % 3) == phase) m |= (1UL << i);
      mask = m;
      stepIdx = (stepIdx + 1) % 3;
      break;
    }

    case M16_RANDOM_SPARKLE: {
      uint8_t k = 1 + (random(0, 3));
      uint32_t m = 0;
      for (uint8_t j = 0; j < k; j++) m |= (1UL << (uint8_t)random(0, N_CH));
      mask = m;
      break;
    }

    case M17_CORNERS_TO_MID_PINGPONG: {
      static const uint8_t seq[4][4] = {
        { 0,  7,  8, 15 },
        { 1,  6,  9, 14 },
        { 2,  5, 10, 13 },
        { 3,  4, 11, 12 }
      };

      mask = 0;
      mask |= (1UL << seq[mode17_step][0]);
      mask |= (1UL << seq[mode17_step][1]);
      mask |= (1UL << seq[mode17_step][2]);
      mask |= (1UL << seq[mode17_step][3]);

      if (mode17_step == 0) mode17_dir = 1;
      else if (mode17_step == 3) mode17_dir = -1;

      uint8_t nextStep = (uint8_t)(mode17_step + mode17_dir);

      if (startupActive && (nextStep == 0) && (mode17_dir == -1)) {
        startupCyclesDone++;
        if (startupCyclesDone >= STARTUP_CYCLES_TARGET) {
          startupActive = false;
          goIdle();
          return;
        }
      }
      mode17_step = nextStep;
      break;
    }

    case M18_ZIGZAG: {
      static const uint8_t seq[16] = {0,8,1,9,2,10,3,11,4,12,5,13,6,14,7,15};
      mask = (1UL << seq[stepIdx]);
      stepIdx = (stepIdx + 1) % 16;
      break;
    }

    case M19_QUADRANT: {
      uint8_t q = (stepIdx / 2) % 4;
      bool on = (stepIdx % 2 == 0);
      mask = on ? quadrantMask(q) : 0UL;

      stepIdx++;
      if (stepIdx >= 8) stepIdx = 0;
      break;
    }

    case M20_WAVE_2STEP: {
      uint8_t q = stepIdx % 4;
      uint8_t prev = (q == 0) ? 3 : (q - 1);
      mask = quadrantMask(q) | quadrantMask(prev);
      stepIdx = (stepIdx + 1) % 4;
      break;
    }

    case M21_EXPAND_TOP_FILL_UNFILL: {
      static const uint8_t seq[14] = {0,1,2,3,4,5,6,7,6,5,4,3,2,1};
      uint8_t r = seq[stepIdx % 14];
      mask = rowPairMask(r);
      stepIdx = (stepIdx + 1) % 14;
      break;
    }

    case M22_EXPAND_BOTTOM_FILL_UNFILL: {
      static const uint8_t seq[12] = {0,1,2,3,4,5,6,5,4,3,2,1};
      uint8_t r = seq[stepIdx % 12];
      mask = rowPairMask(r) | rowPairMask(r + 1);
      stepIdx = (stepIdx + 1) % 12;
      break;
    }

    case M23_SHOW_A:
    case M24_SHOW_B:
      mask = allOnMask();
      break;

    default:
      mask = 0;
      break;
  }

  setMask(mask);
}

// ===================== LINE READER (Serial + BLE) =====================
static bool readLineFromSerialOrBLE(char *out, uint8_t outSize) {
  static char buf[64];
  static uint8_t len = 0;

  auto processChar = [&](char c) -> bool {
    if (c == '\r') return false;
    if (c == '\n') {
      buf[len] = '\0';

      uint8_t start = 0;
      while (buf[start] == ' ' || buf[start] == '\t') start++;

      int end = (int)len - 1;
      while (end >= (int)start && (buf[end] == ' ' || buf[end] == '\t')) {
        buf[end] = '\0';
        end--;
      }

      int rlen = 0;
      for (int i = start; buf[i] != '\0' && rlen < (outSize - 1); i++) out[rlen++] = buf[i];
      out[rlen] = '\0';

      len = 0;
      return true;
    }

    if (len < sizeof(buf) - 1) buf[len++] = c;
    return false;
  };

  while (Serial.available()) {
    if (processChar((char)Serial.read())) return true;
  }

#if USE_BLE
  while (true) {
    char c;
    bool ok;
    portENTER_CRITICAL(&bleMux);
    ok = bleDeq(c);
    portEXIT_CRITICAL(&bleMux);
    if (!ok) break;
    if (processChar(c)) return true;
  }
#endif

  return false;
}

void setup() {
  Serial.begin(115200);
  delay(800);

  EEPROM.begin(EEPROM_SIZE);

  for (uint8_t i = 0; i < N_CH; i++) {
    pinMode(relayPins[i], OUTPUT);
    digitalWrite(relayPins[i], RELAY_ACTIVE_LOW ? HIGH : LOW);
  }
  setMask(0);

  randomSeed((uint32_t)esp_random());
  loadIdleFromEEPROM();

#if USE_BLE
  bleInit();
  Serial.println("BLE ready (NUS). Scan device: LM-ESP32");
#endif

  Serial.print("Idle = "); Serial.println(idleMode);
  Serial.println("Cmd: 1..24 | SPEED 20..5000 | LOW | MED | HIGH | IDLE | STOP | IDLE n");

  startupActive = true;
  startupCyclesDone = 0;
  setMode(M17_CORNERS_TO_MID_PINGPONG);
}

void loop() {
  tickPattern();

  char line[40];
  if (!readLineFromSerialOrBLE(line, sizeof(line))) return;
  if (line[0] == '\0') return;

  startupActive = false;

  for (int i = 0; line[i]; i++) line[i] = (char)toupper((unsigned char)line[i]);

  if (strncmp(line, "SPEED ", 6) == 0) {
    long v = atol(line + 6);
    if (v < 20) v = 20;
    if (v > 5000) v = 5000;
    intervalMs = (unsigned long)v;

    Serial.print("SPEED="); Serial.println(intervalMs);
#if USE_BLE
    bleSendLine("OK\n");
#endif
    return;
  }

  if (strcmp(line, "LOW") == 0)  {
    intervalMs = SPEED_LOW_MS;
    Serial.print("SPEED=LOW "); Serial.println(intervalMs);
#if USE_BLE
    bleSendLine("OK\n");
#endif
    return;
  }

  if (strcmp(line, "MED") == 0)  {
    intervalMs = SPEED_MED_MS;
    Serial.print("SPEED=MED "); Serial.println(intervalMs);
#if USE_BLE
    bleSendLine("OK\n");
#endif
    return;
  }

  if (strcmp(line, "HIGH") == 0) {
    intervalMs = SPEED_HIGH_MS;
    Serial.print("SPEED=HIGH "); Serial.println(intervalMs);
#if USE_BLE
    bleSendLine("OK\n");
#endif
    return;
  }

  if (strcmp(line, "IDLE") == 0) {
    goIdle();
#if USE_BLE
    bleSendLine("OK\n");
#endif
    return;
  }

  if (strcmp(line, "STOP") == 0) {
    setMode(STOP_MODE);
    setMask(0);
#if USE_BLE
    bleSendLine("OK\n");
#endif
    return;
  }

  if (strncmp(line, "IDLE ", 5) == 0) {
    int m = atoi(line + 5);
    if (isAllowedMode(m)) {
      saveIdleToEEPROM((uint8_t)m);
      goIdle();
#if USE_BLE
      bleSendLine("OK\n");
#endif
    } else {
      Serial.println("ERR: IDLE 1..24");
#if USE_BLE
      bleSendLine("ERR: IDLE 1..24\n");
#endif
    }
    return;
  }

  int m = atoi(line);
  if (isAllowedMode(m)) {
    setMode((Mode)m);
#if USE_BLE
    bleSendLine("OK\n");
#endif
  } else {
    if (m != 0 || line[0] == '0') {
      Serial.println("ERR: mode 1..24");
#if USE_BLE
      bleSendLine("ERR: mode 1..24\n");
#endif
    }
  }
}
