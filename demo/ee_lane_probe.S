/* ee_lane_probe.S — empirical lane-semantics probes for the S3 EE unit.
 * Temporary debugging aid for the SAD bit-exactness chase (2026-11-20);
 * safe to delete once the SAD kernel is verified.
 *
 * ee_probe_roundtrip(in16, out16): vld -> vst byte-identity check.
 * ee_probe_zip16(in16, lo16, hi16): expose where ee.vzip.8 (with a zero
 *     second operand) actually places each input byte.
 */
    .text
    .align  4
    .global ee_probe_roundtrip
ee_probe_roundtrip:
    entry   a1, 32
    ee.vld.128.ip   q0, a2, 0
    ee.vst.128.ip   q0, a3, 16
    retw.n

    .align  4
    .global ee_probe_zip16
/* void ee_probe_zip16(const uint8_t *ina, const uint8_t *inb,
 *                     uint8_t *lo, uint8_t *hi)
 * Loads a marker pattern into q1, then zeroes q1 and zips immediately:
 * if ee.zero.q has an async hazard, marker bytes leak into the outputs. */
ee_probe_zip16:
    entry   a1, 32
    ee.vld.128.ip   q0, a2, 0        # q0 = ina (bytes 0..15)
    ee.vld.128.ip   q1, a3, 0        # q1 = marker (bytes 16..31)
    ee.zero.q       q1               # q1 <- 0 ... does it land in time?
    ee.vzip.8       q0, q1
    ee.vst.128.ip   q0, a4, 16
    ee.vst.128.ip   q1, a5, 16
    retw.n
