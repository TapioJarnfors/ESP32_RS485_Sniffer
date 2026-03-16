import struct
import time
import serial

SYNC = b"\xA5\x5A"
HDR_FMT = "<2sIBH"   # sync(2), ts_us(u32), flags(u8), len(u16)
HDR_LEN = struct.calcsize(HDR_FMT)

DLT_USER0 = 147  # LINKTYPE_USER0 in pcapng

def _pad4(n: int) -> int:
    return (4 - (n % 4)) % 4

def _blk(block_type: int, body: bytes) -> bytes:
    total_len = 12 + len(body)
    pad = _pad4(total_len)
    total_len += pad
    return (
        struct.pack("<II", block_type, total_len)
        + body
        + (b"\x00" * pad)
        + struct.pack("<I", total_len)
    )

def _opt(code: int, value: bytes) -> bytes:
    raw = struct.pack("<HH", code, len(value)) + value
    return raw + (b"\x00" * _pad4(len(raw)))

def make_section_header_block() -> bytes:
    body = struct.pack("<IHHq", 0x1A2B3C4D, 1, 0, -1)
    return _blk(0x0A0D0D0A, body)

def make_interface_description_block(linktype: int = DLT_USER0, snaplen: int = 65535) -> bytes:
    body = struct.pack("<HHI", linktype, 0, snaplen)

    # if_tsresol = 10^-6 (microseconds)
    opts = _opt(9, struct.pack("B", 6))
    opts += struct.pack("<HH", 0, 0)  # end of options
    return _blk(0x00000001, body + opts)

def make_enhanced_packet_block(if_id: int, ts_epoch_us: int, payload: bytes) -> bytes:
    ts64 = int(ts_epoch_us)  # microseconds since epoch (IF_TSRESOL=6)

    caplen = len(payload)
    pad = _pad4(caplen)
    pkt_data = payload + (b"\x00" * pad)

    body = struct.pack(
        "<IIIII",
        if_id,
        (ts64 >> 32) & 0xFFFFFFFF,
        ts64 & 0xFFFFFFFF,
        caplen,
        caplen,
    ) + pkt_data

    return _blk(0x00000006, body)

def parse_records(ser):
    buf = bytearray()
    while True:
        chunk = ser.read(4096)
        if not chunk:
            continue
        buf += chunk

        while True:
            idx = buf.find(SYNC)
            if idx < 0:
                if len(buf) > 1:
                    buf = buf[-1:]
                break
            if idx > 0:
                del buf[:idx]

            if len(buf) < HDR_LEN:
                break

            _, ts_us, flags, n = struct.unpack_from(HDR_FMT, buf, 0)
            total = HDR_LEN + n
            if len(buf) < total:
                break

            frame = bytes(buf[HDR_LEN:total])
            del buf[:total]
            yield ts_us, flags, frame

def main():
    port = "COM8"
    baud = 460800
    out_file = "capture_raw_epoch_flags1.pcapng"

    ser = serial.Serial(port, baudrate=baud, timeout=0.2)

    with open(out_file, "wb") as f:
        f.write(make_section_header_block())
        f.write(make_interface_description_block(DLT_USER0, 65535))

        if_id = 0
        offset_us = None

        for esp_ts_us, flags, frame in parse_records(ser):
            if offset_us is None:
                pc_epoch_us = time.time_ns() // 1000
                offset_us = pc_epoch_us - esp_ts_us
                print(f"Anchoring offset_us={offset_us}")

            ts_epoch_us = esp_ts_us + offset_us

            # Embed flags as first byte of packet payload
#*            payload = bytes([flags]) + frame
            payload = frame

            f.write(make_enhanced_packet_block(if_id, ts_epoch_us, payload))

if __name__ == "__main__":
    main()