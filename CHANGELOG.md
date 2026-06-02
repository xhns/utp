## 0.0.1

- Initial version

## 0.1.2

- Send/Receive data
- Send multiple packets
- Send data with selectiveACK
- Send keepalive
- Can communicate with libutp

## 0.2.0

- Change timeout caculator
- Can process FIN message
- Change the window size caculator
- Use dymanic window size and packet size to control data sending

## 0.2.1
- Fix FIN message bug

## 0.3.0
- Change FIN message process logic
- Process RESET message
- Write README


## 0.3.1
- Fix UTP packet parse bug

## 0.4.0
- Implement LEDBAT
- Change packet sending process to improve sending speed.

## 1.0.0
- Fix destroy method bug
- Fix close method bug
- Clear codes

## 1.0.1
- Fix minrtt null bug
- Delete log print

## 1.1.0
- Modernize to Dart 3 (SDK constraint `>=3.0.0 <4.0.0`).
- `UTPSocket` now `implements Socket` instead of `extends Socket` (`Socket`
  became an interface class in Dart 3 and can no longer be extended).
- Migrate lints from `pedantic` to `package:lints/recommended.yaml`; clean
  analyzer to zero errors/warnings/infos (incl. `--fatal-infos`).
- Fix `UTPSocketClient.connect`: the lazily-bound shared `RawDatagramSocket`
  is now stored in a nullable field, restoring the bind-once / reuse behaviour
  (the null-safety migration had broken it with a `late` field).
- Fix close deadlocks: `UTPSocketClient.close()` and `ServerUTPSocket.close()`
  now force-close their UTP sockets before closing the shared UDP socket, and
  `closeForce()` no longer awaits a never-completing `StreamController.close()`
  on an unlistened receive stream. Closing a client/server (or a socket with
  no data listener) used to hang forever.
- Remove dead null checks and unnecessary null assertions left over from the
  null-safety migration; no public API or wire-protocol behaviour changes.
- Expand the test suite: header round-trip per packet type, uint masking,
  payload round-trip, `parseData` edge cases (null/empty/truncated),
  SelectiveACK and unknown-extension handling, `compareSeqLess` wrap-around,
  packet comparison operators, and a loopback connect/send integration test.