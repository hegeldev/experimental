package dev.hegel.protocol;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Manages the underlying byte stream and multiplexes packets across logical {@link Stream}s.
 *
 * <p>A background reader thread reads all incoming packets and dispatches them to the
 * appropriate stream's queue. Writes are serialized via a mutex.
 */
public class Connection {

    public static final String SERVER_CRASHED_MESSAGE =
            "hegel-core server has exited unexpectedly";

    private final OutputStream writer;
    private final Object writeLock = new Object();
    private final Map<Integer, Stream> streams = new ConcurrentHashMap<>();
    private final AtomicBoolean serverExited = new AtomicBoolean(false);
    private final AtomicInteger nextStreamCounter = new AtomicInteger(0);

    private Connection(InputStream reader, OutputStream writer) {
        this.writer = writer;
        startReaderThread(reader);
    }

    /** Create a new {@code Connection} over the given streams. */
    public static Connection create(InputStream reader, OutputStream writer) {
        return new Connection(reader, writer);
    }

    // -----------------------------------------------------------------------
    // Stream management
    // -----------------------------------------------------------------------

    /** Get the control stream (stream ID 0), registering it if needed. */
    public Stream controlStream() {
        return registerStream(0);
    }

    /** Create a new client-initiated stream (odd-numbered ID). */
    public Stream newStream() {
        int counter = nextStreamCounter.incrementAndGet();
        int streamId = (counter << 1) | 1;  // Odd stream IDs for client
        return registerStream(streamId);
    }

    /** Register a stream for the given ID. */
    public Stream connectStream(int streamId) {
        return registerStream(streamId);
    }

    private Stream registerStream(int streamId) {
        Stream stream = new Stream(streamId, this);
        streams.put(streamId, stream);
        // If the server already exited, immediately signal the stream
        if (serverExited.get()) {
            stream.serverExited();
        }
        return stream;
    }

    /** Remove a stream registration (called when stream is closed). */
    void unregisterStream(int streamId) {
        streams.remove(streamId);
    }

    // -----------------------------------------------------------------------
    // Writing
    // -----------------------------------------------------------------------

    /** Send a packet over the connection. */
    void sendPacket(Packet packet) throws IOException {
        synchronized (writeLock) {
            if (serverExited.get()) {
                throw new IOException(SERVER_CRASHED_MESSAGE);
            }
            packet.write(writer);
        }
    }

    // -----------------------------------------------------------------------
    // Background reader thread
    // -----------------------------------------------------------------------

    private void startReaderThread(InputStream reader) {
        Thread thread = new Thread(() -> {
            try {
                while (true) {
                    Packet packet = Packet.read(reader);
                    Stream stream = streams.get(packet.streamId());
                    if (stream != null) {
                        stream.deliver(packet);
                    }
                    // Packets for unknown streams are silently dropped
                }
            } catch (IOException e) {
                // Server exited or connection broken
                serverExited.set(true);
                // Notify all registered streams
                for (Stream stream : streams.values()) {
                    stream.serverExited();
                }
                streams.clear();
            }
        }, "hegel-reader");
        thread.setDaemon(true);
        thread.start();
    }

    public boolean hasServerExited() {
        return serverExited.get();
    }
}
