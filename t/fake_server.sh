#!/bin/bash
# Fake hegel server that writes garbage and exits.
# Used to test handshake failure paths.
echo "NOT_A_VALID_HANDSHAKE"
sleep 0.1
exit 0
