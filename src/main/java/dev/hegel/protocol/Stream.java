package dev.hegel.protocol;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * A single multiplexed logical stream within a {@link Connection}.
 *
 * <p>Packets arriving on this stream's ID are queued here by the background reader thread. Callers
 * use:
 *
 * <ul>
 *   <li>{@link #sendRequest} to send a client-initiated request
 *   <li>{@link #receiveReply} to wait for the server's reply
 *   <li>{@link #sendReply} to reply to a server-initiated request
 *   <li>{@link #receiveRequest} to wait for a server-initiated request
 * </ul>
 */
public class Stream {

  static final int CLOSE_STREAM_MESSAGE_ID = 0x7FFFFFFF;
  static final byte[] CLOSE_STREAM_PAYLOAD = new byte[] {(byte) 0xFE};

  private final int streamId;
  private final Connection connection;
  // All packets from the background reader arrive in this queue
  private final BlockingQueue<Object> inbox; // Packet | SERVER_EXITED sentinel
  // Buffered replies (isReply=true), keyed by message ID
  private final Map<Integer, byte[]> bufferedReplies = new HashMap<>();
  // Buffered incoming requests (isReply=false) from server
  private final List<Packet> bufferedRequests = new ArrayList<>();

  private int nextMessageId = 1;
  private boolean closed = false;

  /** Package-private: configurable timeout for tests (default 30s). */
  static long pollTimeoutSeconds = 30;

  static final Object SERVER_EXITED = new Object();

  Stream(int streamId, Connection connection) {
    this.streamId = streamId;
    this.connection = connection;
    this.inbox = new LinkedBlockingQueue<>();
  }

  public int streamId() {
    return streamId;
  }

  // -----------------------------------------------------------------------
  // Client → Server (client sends request, server replies)
  // -----------------------------------------------------------------------

  /** Send a request packet and return the message ID used. */
  public int sendRequest(byte[] payload) throws IOException {
    checkClosed();
    int msgId = nextMessageId++;
    Packet pkt = new Packet(streamId, msgId, false, payload);
    connection.sendPacket(pkt);
    return msgId;
  }

  /** Wait for a reply to a previously sent request. */
  public byte[] receiveReply(int messageId) throws IOException {
    while (true) {
      byte[] buffered = bufferedReplies.remove(messageId);
      if (buffered != null) return buffered;

      checkClosed();
      Packet pkt = readOnePacket();
      if (pkt.isReply()) {
        if (pkt.messageId() == messageId) {
          return pkt.payload();
        }
        bufferedReplies.put(pkt.messageId(), pkt.payload());
      } else {
        bufferedRequests.add(pkt);
      }
    }
  }

  // -----------------------------------------------------------------------
  // Server → Client (server sends request, client replies)
  // -----------------------------------------------------------------------

  /** Wait for an incoming request from the server. Returns [messageId, payload]. */
  public IncomingRequest receiveRequest() throws IOException {
    while (true) {
      if (!bufferedRequests.isEmpty()) {
        Packet pkt = bufferedRequests.remove(0);
        return new IncomingRequest(pkt.messageId(), pkt.payload());
      }

      checkClosed();
      Packet pkt = readOnePacket();
      if (!pkt.isReply()) {
        return new IncomingRequest(pkt.messageId(), pkt.payload());
      }
      bufferedReplies.put(pkt.messageId(), pkt.payload());
    }
  }

  /** Send a reply to a server-initiated request. */
  public void sendReply(int messageId, byte[] payload) throws IOException {
    Packet pkt = new Packet(streamId, messageId, true, payload);
    connection.sendPacket(pkt);
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  /** Deliver an incoming packet to this stream's queue (called by background reader). */
  void deliver(Packet packet) {
    inbox.offer(packet);
  }

  /** Signal server exit (called by background reader on EOF). */
  void serverExited() {
    inbox.offer(SERVER_EXITED);
  }

  private void checkClosed() throws IOException {
    if (closed) {
      throw new IOException("Stream " + streamId + " is closed");
    }
  }

  private Packet readOnePacket() throws IOException {
    try {
      Object item = inbox.poll(pollTimeoutSeconds, TimeUnit.SECONDS);
      if (item == null) {
        throw new IOException("Timeout waiting for response from hegel-core");
      }
      if (item == SERVER_EXITED) {
        // Put sentinel back so subsequent calls also fail
        inbox.offer(SERVER_EXITED);
        throw new IOException(Connection.SERVER_CRASHED_MESSAGE);
      }
      return (Packet) item;
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new IOException("Interrupted waiting for server response", e);
    }
  }

  /** Mark this stream as closed without sending a close packet. */
  public void markClosed() {
    this.closed = true;
  }

  /** Close the stream and send the close packet to the server. */
  public void close() {
    if (closed) return;
    markClosed();
    connection.unregisterStream(streamId);
    try {
      Packet closePkt = new Packet(streamId, CLOSE_STREAM_MESSAGE_ID, false, CLOSE_STREAM_PAYLOAD);
      connection.sendPacket(closePkt);
    } catch (IOException e) {
      // ignore errors when closing
    }
  }

  /** Result of {@link #receiveRequest()}. */
  public record IncomingRequest(int messageId, byte[] payload) {}
}
