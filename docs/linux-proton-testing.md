# Linux and Proton test notes

The test machine runs CachyOS, with an AMD Radeon RX 7900 XTX (RADV Navi 31) and Proton-CachyOS `11.0-20261015-native`. XCL is built on Linux for `x86_64-pc-windows-msvc` with cargo-xwin and run with the DXVK and vkd3d-proton DLLs bundled with Proton. Each game run used Xvfb, a separate Wine prefix, a read-only game directory, and loopback-only networking.

```sh
RUSTUP_TOOLCHAIN=1.100.0 CL=/FIstring.h \
  cargo xwin build --locked --release -p xcl --target x86_64-pc-windows-msvc
```

`CL=/FIstring.h` works around the include flag that `libudis86-sys` passes to clang-cl.

## Retail title startup

| Build | Last observed result |
| --- | --- |
| Upstream `956a476` with bundled vkd3d-proton | The title reaches `CreateCommandListX`. vkd3d-proton rejects the allocator in `Reset` and returns `0x80070057`. The title triggers a breakpoint. |
| Same build with the native allocator diagnostic | `CreateCommandListX` succeeds. XCL translates 50 pipelines before the title's watchdog path writes to address zero at RVA `0x2215c35`. |
| [PR #162](https://github.com/ivall/xcl/pull/162) `641f551` with the same diagnostic | XCL logs pipeline creation on first use and translates 64 pipelines. The title calls through a null vtable slot at RVA `0x1884fe`. |
| PR #162 `7db28b0` with the diagnostic disabled | The allocator is rejected in `Reset` with `0x80070057`, as in the upstream control. The diagnostic activation message is absent. |
| PR #162 `7db28b0` with `XCL_PROBE_NATIVE_ALLOCATOR=1` | `CreateCommandListX` succeeds. XCL logs pipeline creation on first use and reports 59 pending pipelines at the title's null write at `0x2215c35`. |

On `641f551`, the title calls `[rax+0x48]` on an `ID3D12CommandAllocator` object. That offset is slot 9, immediately after the nine public PC slots. The native allocator satisfies vkd3d-proton's identity check, while the title still needs a console-shaped table. These runs all reported zero `PresentX` calls. The results support the proxy design discussed in [issue #175](https://github.com/ivall/xcl/issues/175).

### Opt-in allocator diagnostic

Set `XCL_PROBE_NATIVE_ALLOCATOR=1` in the environment inherited by `xcl.exe` to leave command allocators on their native vtable. Use the same binary and game with the variable unset for the control. In Proton, set the variable on the Proton invocation or in the container that starts it.

The diagnostic bypasses the XCL allocator `Reset` and `Release` hooks, including recycling and cleanup. The native table can also lack console slots, as observed above. Use it for a bounded startup test. A proxy with stable COM identity and lifetime is the implementation path under consideration.

## Descriptor heap tests from PR #187

The unmodified head `8c0346d` of [PR #187](https://github.com/ivall/xcl/pull/187) passed `gpu_memory_windows_from_the_heap` and `gpu_raw_window_view_reaches_its_top` on the same RX 7900 XTX. The retail run with #187 and the allocator diagnostic logged the shared descriptor heap path, translated 51 pipelines, and stopped at the same watchdog address. The GPU tests were run on the #187 branch as a separate comparison.
