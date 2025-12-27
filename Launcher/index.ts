import { dlopen, FFIType, ptr, CString, JSCallback } from "bun:ffi";
import { join } from "path";

// Load the native library
const libPath = join(import.meta.dir, "native-build", "libLauncher.dylib");

const lib = dlopen(libPath, {
  launcher_show: {
    args: [FFIType.cstring, FFIType.function, FFIType.ptr],
    returns: FFIType.void,
  },
  launcher_hide: {
    args: [],
    returns: FFIType.void,
  },
  launcher_is_visible: {
    args: [],
    returns: FFIType.i32,
  },
  launcher_show_sync: {
    args: [FFIType.cstring, FFIType.ptr, FFIType.i32],
    returns: FFIType.i32,
  },
});

export type LauncherAction = "dismissed" | "submitted" | "command" | "option";

export interface LauncherResult {
  action: LauncherAction;
  query: string | null;
}

const resultMap: Record<number, LauncherAction> = {
  0: "dismissed",
  1: "submitted",
  2: "command",
  3: "option",
};

/**
 * Show the native search launcher (Promise-based)
 */
export async function show(placeholder: string = "Search..."): Promise<LauncherResult> {
  return new Promise((resolve) => {
    const callback = new JSCallback(
      (result: number, queryPtr: number, _ctx: number) => {
        const action = resultMap[result] ?? "dismissed";
        let query: string | null = null;

        if (queryPtr !== 0) {
          query = new CString(queryPtr).toString();
        }

        resolve({ action, query });
        callback.close();
      },
      {
        args: [FFIType.i32, FFIType.ptr, FFIType.ptr],
        returns: FFIType.void,
      }
    );

    lib.symbols.launcher_show(
      Buffer.from(placeholder + "\0"),
      callback.ptr,
      null
    );
  });
}

/**
 * Show launcher synchronously (blocks the thread)
 */
export function showSync(placeholder: string = "Search..."): LauncherResult {
  const bufferSize = 4096;
  const queryBuffer = new Uint8Array(bufferSize);

  const result = lib.symbols.launcher_show_sync(
    Buffer.from(placeholder + "\0"),
    ptr(queryBuffer),
    bufferSize
  );

  const action = resultMap[result] ?? "dismissed";

  let nullIndex = queryBuffer.indexOf(0);
  if (nullIndex === -1) nullIndex = bufferSize;

  const query =
    nullIndex > 0
      ? new TextDecoder().decode(queryBuffer.subarray(0, nullIndex))
      : null;

  return { action, query };
}

/**
 * Hide the launcher programmatically
 */
export function hide(): void {
  lib.symbols.launcher_hide();
}

/**
 * Check if the launcher is currently visible
 */
export function isVisible(): boolean {
  return lib.symbols.launcher_is_visible() !== 0;
}

export default { show, showSync, hide, isVisible };
