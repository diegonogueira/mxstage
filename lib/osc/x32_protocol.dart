// X32/M32 OSC protocol constants.
// All values marked CONFIRM should be verified against the real hardware
// before relying on them in production.

// CONFIRM AGAINST REAL HARDWARE: UDP port used by X32/M32 (XR18 uses 10024).
const int kX32Port = 10023;

// CONFIRM AGAINST REAL HARDWARE: meter bank that carries ch1..32 input levels.
// /meters/13 → 48 floats; indices 0..31 = input channels 1..32.
const String kMeterBank = '/meters/13';

// Subscription to meters expires after 10s; renew every 5s.
const int kMeterRenewIntervalMs = 5000;

// Meter blob update rate from the mixer (~50ms).
const int kMeterUpdateIntervalMs = 50;

// Correction loop interval (must be >> meter interval for anti-oscillation).
const int kCorrectionIntervalMs = 1000;

// Number of input channels on X32.
const int kInputChannelCount = 32;

// Number of mix buses on X32 (1..16).
const int kMixBusCount = 16;
