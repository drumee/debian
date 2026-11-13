#!/bin/bash
function generateRandomPassword() {
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16
}
