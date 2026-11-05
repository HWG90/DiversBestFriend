# The vendored HellForge mod SDK

The headers and licence in this folder are copied unchanged from the `app/sdk` folder of a HellForge 0.3.x installation:
mod SDK version 15 (`HF_MOD_SDK_VERSION 15` in `hellforge_mod.h`). `hellforge_mod.h` is the interface of a code mod;
`hellforge_lua.h` declares the exports of HellForge's loader (the port looks up `hellforge_lua_rewrites` there);
`hellforge_content.h` and `hellforge_components.h` are the content and component headers (the address mapper reads the
stratagem names from `hellforge_content.h`). `LICENSE-SDK` is the SDK's licence, MIT No Attribution (MIT-0): the headers
may be copied and used freely, with no notice required in a mod.

`hellforge/build.sh` compiles the mod, the unit tests and the Wine tests against this folder (`HF_SDK` points the build
elsewhere; the pin is still checked), and `hellforge/tests/check_sdk.sh` fails the build when `HF_MOD_SDK_VERSION` is not
15, when a file here differs from its SHA-256 below, or when a file here is not listed. To move to another SDK: copy its
headers over these, run `sha256sum` on each, update the hashes and the version here and in `check_sdk.sh`, and rebuild
the mod and its tests.

SHA-256 of each file, as `sha256sum` writes them (`check_sdk.sh` reads these lines):

```
ce790f4bd6c820f127f39686d8c94ee0223452bb341783e3136f56f2dd9f73c1  hellforge_mod.h
f9e560249cb9232db8eb48e628b6b4ae5a44c9ad65b4934757104931333f2aad  hellforge_lua.h
2e8006cf56c6582ba2fe9f84e1df03bacdde7ffb48eb945c7f4c68cb34533b03  hellforge_content.h
2bde97bef4bb7f3b955cb9efbf4a65bc9822811f71072df24f93b919275d2695  hellforge_components.h
b4996248adddd1d525636e9298a880a28489ac5000fb1e491e0e5577b0915063  LICENSE-SDK
```
