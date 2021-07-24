# cream changes

## 1.0.0
-----------
* Simplified API; no more multi-get or multi-set (subject to change if need arises).
* Lazy connection pooling via `NimblePool`.
* Increase compatibility with Dalli via serialization that is aware of flags.
* Use `telemetry` for instrumentation.
* Drop dependency on `memcachex`.

## 0.2.0
-----------
* Integrate with `Instrumentation` package

## 0.1.0
-----------
* Initial release
