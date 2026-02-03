#include <EEPROM.h>

// =====================================================
// 16CH Relay - USB + Bluetooth HC-05 (Serial1)
// Fixed Logic: Startup Handler, Smooth Transitions, Safe Input
// =====================================================

#define N_CH 16
const byte relayPins[N_CH] = {22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37};
const bool RELAY_ACTIVE_LOW = true;

unsigned long lastTick = 0;
unsigned long intervalMs = 200;

// --- Speed presets ---
const unsigned long SPEED_LOW_MS  = 200;
const unsigned long SPEED_MED_MS  = 160;
const unsigned long SPEED_HIGH_MS = 120;

// --- Idle Mode ---
const int EEPROM_ADDR_IDLE = 0;
uint8_t idleMode = 3;

// GLOBAL BLINK helper
const uint8_t BLINK3_COUNT = 4;
const uint8_t BLINK3_STEPS = BLINK3_COUNT * 2; 
const unsigned long pauseMs_blink3 = 200;

unsigned long blink3_pauseUntil = 0;
bool blink3_inPause = false;
uint8_t blink3_step = 0;

// ---------- STARTUP sequence ----------
bool startupActive = true;
uint8_t startupCyclesDone = 0;
const uint8_t STARTUP_CYCLES_TARGET = 2;

// ---------- MODE 3 state ----------
const unsigned long pauseMs_mode3 = 200;
unsigned long pauseUntil = 0;
bool mode3_inPause = false;
uint8_t mode3_layer = 0;      
uint8_t mode3_blinkStep = 0;  

// ---------- MODE 4 state ----------
uint8_t mode4_idx = 0;   

// ---------- MODE 5 state ----------
int8_t mode5_dir = 1;
uint8_t mode5_pos = 0;    

// ---------- MODE 6 state ----------
int8_t mode6_dir = 1;
uint8_t mode6_pos = 0;    

// ---------- MODE 7 state ----------
int8_t mode7_dir = 1;
uint8_t mode7_step = 0;   

// ---------- MODE 8 state ----------
int8_t mode8_dir = 1;
uint8_t mode8_step = 0;   

// ---------- MODE 14 state ----------
uint8_t mode14_step = 0;  

// ---------- MODE 17 state ----------
int8_t mode17_dir = 1;     
uint8_t mode17_step = 0;   

// generic
uint8_t stepIdx = 0;

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

// ---------------- Relay helpers ----------------
inline void writePin(byte pin, bool on) {
  digitalWrite(pin, (RELAY_ACTIVE_LOW ? (on ? LOW : HIGH) : (on ? HIGH : LOW)));
}

inline void setMask(uint32_t mask) {
  for (uint8_t i = 0; i < N_CH; i++) {
    writePin(relayPins[i], (mask >> i) & 0x01);
  }
}

inline uint32_t allOnMask() { return ((1UL << N_CH) - 1UL); }

uint32_t oddMask() {
  uint32_t m = 0;
  for (uint8_t i = 0; i < N_CH; i += 2) m |= (1UL << i);
  return m;
}
uint32_t evenMask() {
  uint32_t m = 0;
  for (uint8_t i = 1; i < N_CH; i += 2) m |= (1UL << i);
  return m;
}
uint32_t rangeMask(uint8_t leftIdx, uint8_t rightIdx) {
  uint32_t m = 0;
  for (uint8_t i = leftIdx; i <= rightIdx; i++) m |= (1UL << i);
  return m;
}

// Helper layout: 1-8 kolom kiri, 9-16 kolom kanan
inline uint32_t rowPairMask(uint8_t row) {
  // row 0..7 => (CH row) dan (CH row+8) -> sesuai array index
  // relayPins index 0..7 dan 8..15
  return (1UL << row) | (1UL << (8 + row));
}

uint32_t rowsRangeMask(uint8_t a, uint8_t b) {
  uint32_t m = 0;
  for (uint8_t r = a; r <= b; r++) m |= rowPairMask(r);
  return m;
}

inline uint32_t quadrantMask(uint8_t q) {
  uint8_t start = q * 4;   // 0,4,8,12
  return rangeMask(start, start + 3);
}

// ================= SHOW ENGINE STATE =================
uint8_t show_seg = 0;
bool show_init = true;
unsigned long show_segUntil = 0;

uint8_t show_step = 0;
int8_t  show_dir  = 1;

uint8_t show_m17_step = 0;
int8_t  show_m17_dir  = 1;
bool    show_m17_hitMax = false; 

uint8_t show_m6_pos = 0;   int8_t show_m6_dir = 1;
uint8_t show_m8_step = 0;  int8_t show_m8_dir = 1;
uint8_t show_m4_idx = 0;

uint8_t show_quad = 0;
uint8_t show_oddEven = 0;

void showResetAll() {
  show_seg = 0;
  show_init = true;
  show_segUntil = 0;

  show_step = 0;
  show_dir = 1;

  show_m17_step = 0;
  show_m17_dir = 1;
  show_m17_hitMax = false;

  show_m6_pos = 0; show_m6_dir = 1;
  show_m8_step = 0; show_m8_dir = 1;
  show_m4_idx = 0;

  show_quad = 0;
  show_oddEven = 0;
}

inline void restartShow() {
  showResetAll();
}

// ---------------- Allowed mode ----------------
bool isAllowedMode(int m) {
  return (m >= 1 && m <= 24);
}

// ---------------- Reset state ----------------
void resetStates() {
  stepIdx = 0;
  lastTick = 0;

  // global blink burst
  blink3_step = 0;
  blink3_inPause = false;
  blink3_pauseUntil = 0;

  // mode 3
  mode3_layer = 0;
  mode3_blinkStep = 0;
  mode3_inPause = false;
  pauseUntil = 0;

  // mode 4
  mode4_idx = 0;

  // mode 5
  mode5_dir = 1;
  mode5_pos = 0;

  // mode 6
  mode6_dir = 1;
  mode6_pos = 0;

  // mode 7
  mode7_dir = 1;
  mode7_step = 0;

  // mode 8
  mode8_dir = 1;
  mode8_step = 0;

  // mode 14
  mode14_step = 0;

  // mode 17
  mode17_dir = 1;
  mode17_step = 0;

  showResetAll();
}

void setMode(Mode m) {
  mode = m;
  resetStates();
  // paksa show selalu mulai dari segmen 0 (jaga-jaga)
  if (m == M23_SHOW_A || m == M24_SHOW_B) {
    showResetAll();
  }
  Serial.print("MODE = ");
  if (m == STOP_MODE) Serial.println("STOP");
  else Serial.println((int)m);
}

void goIdle() {
  setMode((Mode)idleMode);
}

void loadIdleFromEEPROM() {
  uint8_t v = EEPROM.read(EEPROM_ADDR_IDLE);
  if (isAllowedMode(v)) idleMode = v;
  else idleMode = 3;
}

void saveIdleToEEPROM(uint8_t m) {
  EEPROM.update(EEPROM_ADDR_IDLE, m);
  idleMode = m;
  Serial.print("IDLE = ");
  Serial.println(idleMode);
}

// ---------------- Pattern runner ----------------
void tickPattern() {
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

    // Mode 3: 4 tengah blink burst BLINK3_COUNT, pause, expand
    case M3_CENTER4_EXPAND_BLINK: {
      if (mode3_inPause) {
        mask = 0;
        if (now >= pauseUntil) mode3_inPause = false;
        setMask(mask);
        return;
      }

      int midLeft  = (N_CH / 2) - 1; // 7
      int midRight = (N_CH / 2);     // 8
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

    // Mode 4: custom runner
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

      if (stepIdx < N) {
        mask = (1UL << (stepIdx + 1)) - 1UL;
      } else {
        uint8_t k = stepIdx - N;
        uint32_t cut = (k == 0) ? 0UL : ((1UL << k) - 1UL);
        mask = full & ~cut;
      }
      stepIdx++;
      if (stepIdx >= (2 * N)) stepIdx = 0;
      break;
    }

    // blink burst atas
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

    // Mode 11: center fill/unfill (berbasis row pair)
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

    // blink burst bawah
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

    // Mode 17: pojok->tengah->pojok + STARTUP 2 siklus lalu idle
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

    // Mode 18: ZigZag
    case M18_ZIGZAG: {
      static const uint8_t seq[16] = {0,8,1,9,2,10,3,11,4,12,5,13,6,14,7,15};
      mask = (1UL << seq[stepIdx]);
      stepIdx = (stepIdx + 1) % 16;
      break;
    }

    // Mode 19: Quadrant PULSE
    case M19_QUADRANT: {
      uint8_t q = (stepIdx / 2) % 4;
      bool on = (stepIdx % 2 == 0);
      mask = on ? quadrantMask(q) : 0UL;

      stepIdx++;
      if (stepIdx >= 8) stepIdx = 0;
      break;
    }

    // Mode 20: Quadrant CHASE tail 2
    case M20_WAVE_2STEP: {
      uint8_t q = stepIdx % 4;
      uint8_t prev = (q == 0) ? 3 : (q - 1);
      mask = quadrantMask(q) | quadrantMask(prev);

      stepIdx = (stepIdx + 1) % 4;
      break;
    }

    // Mode 21: Row-pair runner pingpong 1 bar
    case M21_EXPAND_TOP_FILL_UNFILL: {
      static const uint8_t seq[14] = {0,1,2,3,4,5,6,7,6,5,4,3,2,1};
      uint8_t r = seq[stepIdx % 14];
      mask = rowPairMask(r);
      stepIdx = (stepIdx + 1) % 14;
      break;
    }

    // Mode 22: Row-pair runner 2 bar tebal pingpong
    case M22_EXPAND_BOTTOM_FILL_UNFILL: {
      static const uint8_t seq[12] = {0,1,2,3,4,5,6,5,4,3,2,1};
      uint8_t r = seq[stepIdx % 12]; // r 0..6
      mask = rowPairMask(r) | rowPairMask(r + 1);
      stepIdx = (stepIdx + 1) % 12;
      break;
    }

    case M23_SHOW_A: {
      // durasi segmen (ms), dur=0 => tunggu selesai 1 siklus M17
      static const uint16_t dur[] = { 800, 0, 2400, 2000, 2000, 800, 1800 };
      const uint8_t SEG_N = sizeof(dur)/sizeof(dur[0]);

      if (show_init) {
        show_init = false;

        if (show_seg == 0) { show_step = 0; }
        if (show_seg == 1) { show_m17_step = 0; show_m17_dir = 1; show_m17_hitMax = false; }
        if (show_seg == 2) { show_m6_pos = 0; show_m6_dir = 1; }
        if (show_seg == 3) { show_m8_step = 0; show_m8_dir = 1; }
        if (show_seg == 4) { show_m4_idx = 0; }
        if (show_seg == 5) { show_step = 0; }

        show_segUntil = (dur[show_seg] == 0) ? 0 : (now + dur[show_seg]);
      }

      if (show_segUntil != 0 && now >= show_segUntil) {
        show_seg++;
        show_init = true;
        if (show_seg >= SEG_N) { restartShow(); return; }
        break;
      }

      switch (show_seg) {
        // 0) FULL burst 2x
        case 0: {
          bool on = (show_step % 2 == 0);
          mask = on ? allOnMask() : 0UL;
          show_step++;
          if (show_step >= 4) show_step = 0;
          break;
        }

        // 1) M17 1 siklus pojok->tengah->pojok
        case 1: {
          static const uint8_t seq[4][4] = {
            { 0,  7,  8, 15 },
            { 1,  6,  9, 14 },
            { 2,  5, 10, 13 },
            { 3,  4, 11, 12 }
          };

          mask = 0;
          mask |= (1UL << seq[show_m17_step][0]);
          mask |= (1UL << seq[show_m17_step][1]);
          mask |= (1UL << seq[show_m17_step][2]);
          mask |= (1UL << seq[show_m17_step][3]);

          // FIX: Cek jika ini frame terakhir (step 0, setelah dari tengah)
          if (show_m17_step == 0 && show_m17_hitMax && show_m17_dir == -1) {
             show_m17_hitMax = false;
             show_seg++;
             show_init = true;
             // Tidak break, biarkan mask step 0 ditampilkan tick ini
          } else {
            if (show_m17_step == 0) show_m17_dir = 1;
            if (show_m17_step == 3) { show_m17_dir = -1; show_m17_hitMax = true; }
            show_m17_step = (uint8_t)(show_m17_step + show_m17_dir);
          }
          break;
        }

        // 2) M6 in-out pingpong pairs
        case 2: {
          static const uint8_t s[8] = {0, 14, 2, 12, 4, 10, 6, 8};
          uint8_t left = s[show_m6_pos];
          mask = (1UL << left) | (1UL << (left + 1));

          if (show_m6_pos == 0) show_m6_dir = 1;
          else if (show_m6_pos == 7) show_m6_dir = -1;
          show_m6_pos = (uint8_t)(show_m6_pos + show_m6_dir);
          break;
        }

        // 3) M8 horizontal pingpong
        case 3: {
          static const uint8_t L[8] = { 0, 1, 2, 3, 11, 10, 9, 8 };
          static const uint8_t R[8] = { 7, 6, 5, 4, 12, 13, 14, 15 };
          mask = (1UL << L[show_m8_step]) | (1UL << R[show_m8_step]);

          if (show_m8_step == 0) show_m8_dir = 1;
          else if (show_m8_step == 7) show_m8_dir = -1;
          show_m8_step = (uint8_t)(show_m8_step + show_m8_dir);
          break;
        }

        // 4) M4 custom runner
        case 4: {
          static const uint8_t seq4[] = {
            15,14,13,12,11,10,9,8,
            9,10,11,
            4,5,6,7,
            6,5,4,3,2,1,0,
            1,2,3,
            12,13,14
          };
          const uint8_t L4 = sizeof(seq4)/sizeof(seq4[0]);
          mask = (1UL << seq4[show_m4_idx]);
          show_m4_idx++;
          if (show_m4_idx >= L4) show_m4_idx = 0;
          break;
        }

        // 5) STROBE full 3x
        case 5: {
          bool on = (show_step % 2 == 0);
          mask = on ? allOnMask() : 0UL;
          show_step++;
          if (show_step >= 6) show_step = 0;
          break;
        }

        // 6) Sparkle ending
        case 6: {
          uint8_t k = 1 + (random(0, 3));
          uint32_t m = 0;
          for (uint8_t j = 0; j < k; j++) m |= (1UL << (uint8_t)random(0, N_CH));
          mask = m;
          break;
        }
      }
      break;
    }

    // =======================
    // MODE 24: SHOW B (Mechanical March)
    // =======================
    case M24_SHOW_B: {
      static const uint16_t dur[] = { 2200, 2000, 2200, 1800, 0 };
      const uint8_t SEG_N = sizeof(dur)/sizeof(dur[0]);

      if (show_init) {
        show_init = false;

        if (show_seg == 0) { show_quad = 0; }
        if (show_seg == 1) { show_step = 0; }
        if (show_seg == 2) { show_step = 0; }
        if (show_seg == 3) { show_oddEven = 0; }
        if (show_seg == 4) { show_m17_step = 0; show_m17_dir = 1; show_m17_hitMax = false; }

        show_segUntil = (dur[show_seg] == 0) ? 0 : (now + dur[show_seg]);
      }

      if (show_segUntil != 0 && now >= show_segUntil) {
        show_seg++;
        show_init = true;
        if (show_seg >= SEG_N) { restartShow(); return; }
        break;
      }

      switch (show_seg) {
        // 0) Quadrant chase (tail 2 quadrant)
        case 0: {
          uint8_t q = show_quad % 4;
          uint8_t prev = (q == 0) ? 3 : (q - 1);
          mask = quadrantMask(q) | quadrantMask(prev);
          show_quad = (show_quad + 1) % 4;
          break;
        }

        // 1) ZigZag
        case 1: {
          static const uint8_t zz[16] = {0,8,1,9,2,10,3,11,4,12,5,13,6,14,7,15};
          mask = (1UL << zz[show_step]);
          show_step = (show_step + 1) % 16;
          break;
        }

        // 2) Row-pair runner tebal 2 baris pingpong
        case 2: {
          static const uint8_t seq[12] = {0,1,2,3,4,5,6,5,4,3,2,1};
          uint8_t r = seq[show_step % 12];   // r 0..6
          mask = rowPairMask(r) | rowPairMask(r + 1);
          show_step = (show_step + 1) % 12;
          break;
        }

        // 3) Odd/Even pulse
        case 3: {
          mask = (show_oddEven == 0) ? oddMask() : evenMask();
          show_oddEven ^= 1;
          break;
        }

        // 4) M17 1 siklus lalu idle (FIX: transisi mulus)
        case 4: {
          static const uint8_t seq[4][4] = {
            { 0,  7,  8, 15 },
            { 1,  6,  9, 14 },
            { 2,  5, 10, 13 },
            { 3,  4, 11, 12 }
          };

          mask = 0;
          mask |= (1UL << seq[show_m17_step][0]);
          mask |= (1UL << seq[show_m17_step][1]);
          mask |= (1UL << seq[show_m17_step][2]);
          mask |= (1UL << seq[show_m17_step][3]);

          if (show_m17_step == 0 && show_m17_hitMax && show_m17_dir == -1) {
            restartShow();
            return;
          } else {
            if (show_m17_step == 0) show_m17_dir = 1;
            if (show_m17_step == 3) { show_m17_dir = -1; show_m17_hitMax = true; }
            show_m17_step = (uint8_t)(show_m17_step + show_m17_dir);
          }
          break;
        }
      }
      break;
    }

    default:
      mask = 0;
      break;
  }

  setMask(mask);
}

// ---------------- Line reader SAFE ----------------
bool readLineFromBoth(char *out, uint8_t outSize) {
  static char buf[64];
  static uint8_t len = 0;

  auto processChar = [&](char c) -> bool {
    if (c == '\r') return false;
    if (c == '\n') {
      buf[len] = '\0';

      // Trim depan
      uint8_t start = 0;
      while (buf[start] == ' ' || buf[start] == '\t') start++;
      
      // Trim belakang
      int end = len - 1;
      while (end >= start && (buf[end] == ' ' || buf[end] == '\t')) {
        buf[end] = '\0';
        end--;
      }
      
      // Copy
      int resultLen = 0;
      for (int i = start; buf[i] != '\0' && resultLen < (outSize - 1); i++) {
        out[resultLen++] = buf[i];
      }
      out[resultLen] = '\0';

      len = 0;
      return true;
    }

    if (len < sizeof(buf) - 1) buf[len++] = c;
    return false;
  };

  while (Serial.available()) {
    if (processChar((char)Serial.read())) return true;
  }
  while (Serial1.available()) {
    if (processChar((char)Serial1.read())) return true;
  }
  return false;
}

void setup() {
  Serial.begin(115200);
  Serial1.begin(9600); // HC-05 default

  for (uint8_t i = 0; i < N_CH; i++) pinMode(relayPins[i], OUTPUT);
  setMask(0);

  randomSeed(analogRead(A0));
  loadIdleFromEEPROM();

  Serial.print("Idle = "); Serial.println(idleMode);
  Serial.println("Cmd: 1..24 | SPEED 20..5000 | LOW | MED | HIGH | IDLE | STOP");

  // Startup: Mode 17 jalan 2 siklus lalu auto ke idle
  startupActive = true;
  startupCyclesDone = 0;
  setMode(M17_CORNERS_TO_MID_PINGPONG);
}

void loop() {
  tickPattern();

  char line[40];
  if (!readLineFromBoth(line, sizeof(line))) return;
  if (line[0] == '\0') return;

  // FIX: User intervensi -> matikan startup logic
  startupActive = false;

  for (int i = 0; line[i]; i++) line[i] = toupper(line[i]);

  if (strncmp(line, "SPEED ", 6) == 0) {
    long v = atol(line + 6);
    if (v < 20) v = 20;
    if (v > 5000) v = 5000;
    intervalMs = (unsigned long)v;
    Serial.print("SPEED="); Serial.println(intervalMs);
    return;
  }

  if (strcmp(line, "LOW") == 0) {
    intervalMs = SPEED_LOW_MS;
    Serial.print("SPEED=LOW "); Serial.println(intervalMs);
    return;
  }
  if (strcmp(line, "MED") == 0) {
    intervalMs = SPEED_MED_MS;
    Serial.print("SPEED=MED "); Serial.println(intervalMs);
    return;
  }
  if (strcmp(line, "HIGH") == 0) {
    intervalMs = SPEED_HIGH_MS;
    Serial.print("SPEED=HIGH "); Serial.println(intervalMs);
    return;
  }

  if (strcmp(line, "IDLE") == 0) {
    goIdle();
    return;
  }

  if (strcmp(line, "STOP") == 0) {
    setMode(STOP_MODE);
    setMask(0);
    return;
  }

  if (strncmp(line, "IDLE ", 5) == 0) {
    int m = atoi(line + 5);
    if (isAllowedMode(m)) {
      saveIdleToEEPROM((uint8_t)m);
      goIdle();
    } else {
      Serial.println("ERR: IDLE 1..24");
    }
    return;
  }

  int m = atoi(line);
  if (isAllowedMode(m)) {
    setMode((Mode)m);
  } else {
    // Abaikan input sampah, hanya komplain jika angka salah
    if (m != 0 || line[0] == '0') {
      Serial.println("ERR: mode 1..24");
    }
  }
}