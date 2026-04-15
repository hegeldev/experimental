#!/usr/bin/env python3
"""
Mock server for testing runner.rkt error paths.

Set MOCK_SERVER_MODE env var before running:
  Modes:
    health_check_failure       - sends test_done with health_check_failure result
    flaky                      - sends test_done with flaky result
    else_loop                  - sends an unknown event before test_done
    missing_keys               - sends test_done without interesting_test_cases/passed keys
    passed_false_no_replay     - sends test_done with passed=False, interesting_test_cases=0
"""

import os
import sys
import cbor2

# Add hegel-core to path
sys.path.insert(0, '/home/dev/.local/share/uv/tools/hegel-core/lib/python3.13/site-packages')

from hegel.protocol.connection import Connection


class StdioTransport:
    def recv(self, n):
        data = sys.stdin.buffer.read(n)
        return data if data else b''
    def sendall(self, data):
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
    def settimeout(self, t): pass
    def shutdown(self, h): pass
    def close(self): pass


def main():
    mode = os.environ.get('MOCK_SERVER_MODE', 'health_check_failure')

    conn = Connection(StdioTransport())
    conn.receive_handshake()

    # Read run_test command
    packet = conn.control_stream.read_request()
    message = cbor2.loads(packet.payload)
    test_stream = conn.register_client_stream(message['stream_id'], role='Test stream')
    conn.control_stream.write_reply(packet.message_id, True)

    if mode == 'health_check_failure':
        # Send test_done with health_check_failure
        test_stream.send_request({
            'event': 'test_done',
            'results': {
                'passed': True,
                'health_check_failure': 'HealthCheck.filter_too_much exceeded',
                'interesting_test_cases': 0,
            },
        }).get()

    elif mode == 'flaky':
        # Send test_done with flaky
        test_stream.send_request({
            'event': 'test_done',
            'results': {
                'passed': True,
                'flaky': 'Test gave different results on different runs',
                'interesting_test_cases': 0,
            },
        }).get()

    elif mode == 'else_loop':
        # Send an unknown event type, then test_done
        test_stream.send_request({
            'event': 'unknown_event_type',
            'data': 'some payload',
        }).get()
        test_stream.send_request({
            'event': 'test_done',
            'results': {
                'passed': True,
                'interesting_test_cases': 0,
            },
        }).get()

    elif mode == 'missing_keys':
        # Send test_done without the expected result keys (to cover default values)
        test_stream.send_request({
            'event': 'test_done',
            'results': {},  # Missing 'passed', 'interesting_test_cases'
        }).get()

    elif mode == 'passed_false_no_replay':
        # Send test_done with passed=False but interesting_test_cases=0
        # Covers the "unknown" fallback message in run-hegel
        test_stream.send_request({
            'event': 'test_done',
            'results': {
                'passed': False,
                'interesting_test_cases': 0,
            },
        }).get()


if __name__ == '__main__':
    main()
