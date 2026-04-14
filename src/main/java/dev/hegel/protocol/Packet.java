package dev.hegel.protocol;

import java.io.DataInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.zip.CRC32;

/**
 * A single wire protocol packet.
 *
 * <p>Frame format (21+ bytes):
 * <ul>
 *   <li>4 bytes: magic {@code 0x4845474C} ("HEGL")</li>
 *   <li>4 bytes: CRC32 of the header (checksum field zeroed) + payload</li>
 *   <li>4 bytes: stream ID</li>
 *   <li>4 bytes: message ID (high bit set → reply)</li>
 *   <li>4 bytes: payload length</li>
 *   <li>N bytes: CBOR payload</li>
 *   <li>1 byte:  terminator {@code 0x0A}</li>
 * </ul>
 */
public record Packet(int streamId, int messageId, boolean isReply, byte[] payload) {

    static final int MAGIC = 0x4845474C;
    static final int HEADER_SIZE = 20;
    static final byte TERMINATOR = 0x0A;
    static final int REPLY_BIT = 0x80000000;

    // -----------------------------------------------------------------------
    // Write
    // -----------------------------------------------------------------------

    /** Encode and write this packet to {@code out}. */
    public void write(OutputStream out) throws IOException {
        int msgIdRaw = isReply ? (messageId | REPLY_BIT) : messageId;

        byte[] header = new byte[HEADER_SIZE];
        writeInt(header, 0, MAGIC);
        // checksum placeholder at [4..8] left as zeros
        writeInt(header, 8, streamId);
        writeInt(header, 12, msgIdRaw);
        writeInt(header, 16, payload.length);

        // CRC32 over header (checksum zeroed) + payload
        CRC32 crc = new CRC32();
        crc.update(header);
        crc.update(payload);
        long checksum = crc.getValue();
        writeInt(header, 4, (int) checksum);

        out.write(header);
        out.write(payload);
        out.write(TERMINATOR);
        out.flush();
    }

    // -----------------------------------------------------------------------
    // Read
    // -----------------------------------------------------------------------

    /** Read exactly one packet from {@code in}. */
    public static Packet read(InputStream in) throws IOException {
        DataInputStream din = new DataInputStream(in);

        byte[] header = new byte[HEADER_SIZE];
        din.readFully(header);

        int magic    = readInt(header, 0);
        int checksum = readInt(header, 4);
        int streamId = readInt(header, 8);
        int msgIdRaw = readInt(header, 12);
        int length   = readInt(header, 16);

        if (magic != MAGIC) {
            throw new IOException(String.format(
                    "Invalid magic: expected 0x%08X, got 0x%08X", MAGIC, magic));
        }

        boolean isReply = (msgIdRaw & REPLY_BIT) != 0;
        int messageId   = msgIdRaw & ~REPLY_BIT;

        if (length < 0) {
            throw new IOException("Invalid payload length: " + length);
        }
        byte[] payload = new byte[length];
        din.readFully(payload);

        int terminator = in.read();
        if (terminator != (TERMINATOR & 0xFF)) {
            throw new IOException(String.format(
                    "Invalid terminator: expected 0x0A, got 0x%02X", terminator));
        }

        // Verify CRC32
        byte[] headerForCheck = header.clone();
        writeInt(headerForCheck, 4, 0);
        CRC32 crc = new CRC32();
        crc.update(headerForCheck);
        crc.update(payload);
        long computed = crc.getValue();
        if ((int) computed != checksum) {
            throw new IOException(String.format(
                    "CRC32 mismatch: expected 0x%08X, got 0x%08X", checksum, (int) computed));
        }

        return new Packet(streamId, messageId, isReply, payload);
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private static void writeInt(byte[] buf, int offset, int value) {
        buf[offset]     = (byte) (value >>> 24);
        buf[offset + 1] = (byte) (value >>> 16);
        buf[offset + 2] = (byte) (value >>>  8);
        buf[offset + 3] = (byte)  value;
    }

    private static int readInt(byte[] buf, int offset) {
        return ((buf[offset]     & 0xFF) << 24)
             | ((buf[offset + 1] & 0xFF) << 16)
             | ((buf[offset + 2] & 0xFF) <<  8)
             |  (buf[offset + 3] & 0xFF);
    }
}
